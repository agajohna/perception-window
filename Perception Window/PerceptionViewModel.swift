//
//  PerceptionViewModel.swift
//  Perception Window
//

import AVFoundation
import Foundation
import Observation
import SwiftUI

@Observable
final class PerceptionViewModel {
    private(set) var isPerceiving = false
    private(set) var focusProgress: Double = 0
    private(set) var displayedObservation: PerceptionObservation?
    private(set) var observationOpacity: Double = 0

    private let demoService = DemoPerceptionService()
    private let analysisService = AnalysisService()
    private let observationStore = ObservationStore()

    private var latestJPEG: Data?
    private var samplingTask: Task<Void, Never>?
    private var focusTask: Task<Void, Never>?
    private var transitionTask: Task<Void, Never>?
    private var isAnalysisInFlight = false
    private var pendingObservation: PerceptionObservation?
    private var focusIsComplete = false

    private let frameRelay = FrameRelay()

    func attach(to camera: CameraService) {
        frameRelay.onJPEG = { [weak self] jpeg in
            Task { @MainActor in
                self?.updateLatestFrame(jpeg)
            }
        }

        camera.onFrame = { [frameRelay] sampleBuffer in
            frameRelay.process(sampleBuffer)
        }
    }

    func begin() {
        isPerceiving = true
        focusProgress = 0
        focusIsComplete = false
        displayedObservation = nil
        observationOpacity = 0
        pendingObservation = nil

        startFocusFill()
        startSamplingLoop()
    }

    func end() {
        isPerceiving = false
        samplingTask?.cancel()
        focusTask?.cancel()
        transitionTask?.cancel()
        isAnalysisInFlight = false
        pendingObservation = nil
        focusIsComplete = false

        Task { @MainActor in
            withAnimation(.easeOut(duration: 0.25)) {
                focusProgress = 0
                observationOpacity = 0
            }
            try? await Task.sleep(for: .milliseconds(250))
            displayedObservation = nil
            latestJPEG = nil
        }
    }

    private func updateLatestFrame(_ jpeg: Data) {
        guard isPerceiving else { return }
        latestJPEG = jpeg
    }

    private func startFocusFill() {
        focusTask?.cancel()
        focusTask = Task { [weak self] in
            let steps = 50
            let interval = PerceptionConfiguration.focusFillDuration / Double(steps)

            for step in 1...steps {
                try? await Task.sleep(for: .seconds(interval))
                guard !Task.isCancelled, self?.isPerceiving == true else { return }

                await MainActor.run {
                    self?.focusProgress = Double(step) / Double(steps)
                }
            }

            await MainActor.run {
                self?.focusIsComplete = true
                self?.tryRevealPendingObservation()
            }
        }
    }

    private func startSamplingLoop() {
        samplingTask?.cancel()
        samplingTask = Task { [weak self] in
            await self?.sampleAndAnalyze()

            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(PerceptionConfiguration.resampleInterval))
                guard !Task.isCancelled else { break }
                await self?.sampleAndAnalyze()
            }
        }
    }

    private func sampleAndAnalyze() async {
        guard isPerceiving, !isAnalysisInFlight else { return }

        if latestJPEG == nil {
            try? await Task.sleep(for: .milliseconds(200))
        }

        guard let jpeg = latestJPEG else { return }

        isAnalysisInFlight = true
        defer { isAnalysisInFlight = false }

        let result: AnalysisResult
        if PerceptionConfiguration.useDemoPerception {
            result = await demoService.perceive(
                jpeg: jpeg,
                profile: PerceptionConfiguration.curiosityProfile
            )
        } else {
            do {
                result = try await analysisService.analyze(jpeg: jpeg)
            } catch {
                return
            }
        }

        guard isPerceiving else { return }

        if !PerceptionConfiguration.useDemoPerception {
            _ = try? await observationStore.save(frameJPEG: jpeg, result: result)
        }

        apply(result)
    }

    private func apply(_ result: AnalysisResult) {
        switch result.outcome {
        case .observation(let observation):
            if let domain = observation.domain {
                var profile = PerceptionConfiguration.curiosityProfile
                profile.reinforce(domain)
                PerceptionConfiguration.curiosityProfile = profile
            }

            pendingObservation = observation
            tryRevealPendingObservation()
        case .nothingVisible:
            break
        }
    }

    private func tryRevealPendingObservation() {
        guard isPerceiving, focusIsComplete, let observation = pendingObservation else { return }

        if let current = displayedObservation {
            if current.primary == observation.primary {
                withAnimation(.easeOut(duration: 0.35)) {
                    displayedObservation = observation
                }
                return
            }
            transitionTo(observation)
        } else {
            displayedObservation = observation
            withAnimation(.easeOut(duration: PerceptionConfiguration.observationFadeDuration)) {
                observationOpacity = 1
            }
        }
    }

    private func transitionTo(_ observation: PerceptionObservation) {
        transitionTask?.cancel()
        transitionTask = Task { [weak self] in
            await MainActor.run {
                withAnimation(.easeOut(duration: PerceptionConfiguration.observationFadeDuration)) {
                    self?.observationOpacity = 0
                }
            }

            try? await Task.sleep(for: .seconds(PerceptionConfiguration.observationFadeDuration))
            guard !Task.isCancelled, self?.isPerceiving == true else { return }

            await MainActor.run {
                self?.displayedObservation = nil
            }

            try? await Task.sleep(for: .seconds(PerceptionConfiguration.attentionTransitionPause))
            guard !Task.isCancelled, self?.isPerceiving == true else { return }

            await MainActor.run {
                self?.displayedObservation = observation
                withAnimation(.easeOut(duration: PerceptionConfiguration.observationFadeDuration)) {
                    self?.observationOpacity = 1
                }
            }
        }
    }
}

// MARK: - Frame relay

private final class FrameRelay: @unchecked Sendable {
    var onJPEG: (@Sendable (Data) -> Void)?

    private var lastCaptureTime: TimeInterval = 0
    private let lock = NSLock()

    func process(_ sampleBuffer: CMSampleBuffer) {
        let now = CACurrentMediaTime()

        lock.lock()
        defer { lock.unlock() }

        guard now - lastCaptureTime > 0.15 else { return }
        lastCaptureTime = now

        guard let jpeg = FrameCapture.jpeg(from: sampleBuffer) else { return }
        onJPEG?(jpeg)
    }
}
