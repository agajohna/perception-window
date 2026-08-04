//
//  PerceptionViewModel.swift
//  Perception Window
//

import AVFoundation
import Foundation
import Observation
import SwiftUI

#if os(iOS)
import UIKit
#endif

@Observable
final class PerceptionViewModel {
    private(set) var isPerceiving = false
    private(set) var focusProgress: Double = 0
    private(set) var displayedObservation: PerceptionObservation?
    private(set) var observationOpacity: Double = 0

    private let subjectIdentifier = SubjectIdentifier()
    private let entityRegistry = EntityRegistry()
    private let continuityService = ContinuityService()
    private let analysisService = AnalysisService()
    private let observationStore = ObservationStore()

    private var latestJPEG: Data?
    private var samplingTask: Task<Void, Never>?
    private var focusTask: Task<Void, Never>?
    private var transitionTask: Task<Void, Never>?
    private var isAnalysisInFlight = false
    private var pendingObservation: PerceptionObservation?
    private var focusIsComplete = false

    /// Last completed inspection per entity — drives session vs revisit behavior.
    private var lastInspectionByEntity: [UUID: Date] = [:]
    private var currentEntityID: UUID?

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
        currentEntityID = nil

        startFocusFill()
        startSamplingLoop()
    }

    func end() {
        if let entityID = currentEntityID {
            lastInspectionByEntity[entityID] = Date()
            Task {
                await entityRegistry.recordVisit(for: entityID)
            }
        }

        isPerceiving = false
        samplingTask?.cancel()
        focusTask?.cancel()
        transitionTask?.cancel()
        isAnalysisInFlight = false
        pendingObservation = nil
        focusIsComplete = false
        currentEntityID = nil

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

        let profile = PerceptionConfiguration.curiosityProfile
        let cameraMetadata = Self.cameraMetadata(for: jpeg)
        let result: AnalysisResult
        var identity: SubjectIdentity?
        var comparisonStrategy: ComparisonStrategy?

        if let resolution = await subjectIdentifier.identify(jpeg: jpeg, profile: profile) {
            let entity = await entityRegistry.resolve(
                temporarySubjectKey: resolution.temporarySubjectKey,
                matchConfidence: resolution.matchConfidence
            )
            identity = SubjectIdentity(resolution: resolution, entity: entity)
            currentEntityID = entity.id

            let isSameSession = Self.isSameSession(
                entityID: entity.id,
                lastInspectionByEntity: lastInspectionByEntity
            )
            let hasBaseline = await observationStore.hasBaseline(forEntity: entity.id)
            let comparison = await observationStore.comparisonTarget(
                forEntity: entity.id,
                revisitInterval: PerceptionConfiguration.continuityRevisitInterval
            )
            comparisonStrategy = comparison?.strategy

            var comparisonJPEG: Data?
            if let comparison {
                comparisonJPEG = await observationStore.frameJPEG(for: comparison.record)
            }

            result = await continuityService.perceive(
                jpeg: jpeg,
                identity: identity!,
                comparison: comparison,
                comparisonJPEG: comparisonJPEG,
                hasBaseline: hasBaseline,
                isSameSession: isSameSession,
                useDemoFirstVisit: PerceptionConfiguration.useDemoPerception
            )
        } else if PerceptionConfiguration.useDemoPerception {
            result = .silent(.noSubjectIdentified, rawResponse: "identify:none")
        } else {
            do {
                result = try await analysisService.analyze(jpeg: jpeg)
            } catch {
                result = .silent(.modelFailure, rawResponse: "analyze:\(error)")
            }
        }

        guard isPerceiving else { return }

        await persistIfNeeded(
            jpeg: jpeg,
            identity: identity,
            result: result,
            cameraMetadata: cameraMetadata,
            comparisonStrategy: comparisonStrategy
        )

        apply(result)
    }

    private func persistIfNeeded(
        jpeg: Data,
        identity: SubjectIdentity?,
        result: AnalysisResult,
        cameraMetadata: CameraCaptureMetadata?,
        comparisonStrategy: ComparisonStrategy?
    ) async {
        switch result.outcome {
        case .observation:
            if let entityID = identity?.persistentEntityID {
                _ = try? await observationStore.save(
                    frameJPEG: jpeg,
                    entityID: entityID,
                    identity: identity,
                    result: result,
                    cameraMetadata: cameraMetadata,
                    comparisonStrategy: comparisonStrategy
                )
            }
        case .silent(let reason):
            guard reason != .sameSessionContinuation else { return }

            if result.isBaseline, let entityID = identity?.persistentEntityID {
                _ = try? await observationStore.save(
                    frameJPEG: jpeg,
                    entityID: entityID,
                    identity: identity,
                    result: result,
                    cameraMetadata: cameraMetadata,
                    comparisonStrategy: comparisonStrategy
                )
                return
            }

            if reason == .noMeaningfulChange, let entityID = identity?.persistentEntityID {
                _ = try? await observationStore.save(
                    frameJPEG: jpeg,
                    entityID: entityID,
                    identity: identity,
                    result: result,
                    cameraMetadata: cameraMetadata,
                    comparisonStrategy: comparisonStrategy
                )
            }
        }
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
        case .silent:
            break
        }
    }

    private static func isSameSession(entityID: UUID, lastInspectionByEntity: [UUID: Date]) -> Bool {
        guard let last = lastInspectionByEntity[entityID] else { return false }
        return Date().timeIntervalSince(last) < PerceptionConfiguration.continuityRevisitInterval
    }

    private static func cameraMetadata(for jpeg: Data) -> CameraCaptureMetadata {
        #if os(iOS)
        if let image = UIImage(data: jpeg) {
            return CameraCaptureMetadata(
                imageWidth: Int(image.size.width * image.scale),
                imageHeight: Int(image.size.height * image.scale),
                jpegByteCount: jpeg.count
            )
        }
        #endif
        return CameraCaptureMetadata(jpegByteCount: jpeg.count)
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
