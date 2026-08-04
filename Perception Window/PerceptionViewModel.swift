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
    private let requestBudget = AnalysisRequestBudget()

    private var frameSelector = FrameSelector()
    private var focusTask: Task<Void, Never>?
    private var transitionTask: Task<Void, Never>?
    private var analysisTask: Task<Void, Never>?
    private var pendingObservation: PerceptionObservation?
    private var focusIsComplete = false
    private var analysisCompletedForHold = false

    private var lastInspectionByEntity: [UUID: Date] = [:]
    private var currentEntityID: UUID?

    private let frameRelay = FrameRelay()

    func attach(to camera: CameraService) {
        frameRelay.onJPEG = { [weak self] jpeg in
            Task { @MainActor in
                self?.accumulateFrame(jpeg)
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
        analysisCompletedForHold = false
        displayedObservation = nil
        observationOpacity = 0
        pendingObservation = nil
        currentEntityID = nil
        frameSelector.reset()

        Task { await requestBudget.beginHold() }
        startFocusFill()
    }

    func end() {
        if let entityID = currentEntityID {
            lastInspectionByEntity[entityID] = Date()
            Task { await entityRegistry.recordVisit(for: entityID) }
        }

        isPerceiving = false
        focusTask?.cancel()
        transitionTask?.cancel()
        analysisTask?.cancel()
        pendingObservation = nil
        focusIsComplete = false
        currentEntityID = nil
        frameSelector.reset()

        Task { @MainActor in
            withAnimation(.easeOut(duration: 0.25)) {
                focusProgress = 0
                observationOpacity = 0
            }
            try? await Task.sleep(for: .milliseconds(250))
            displayedObservation = nil
        }
    }

    /// Camera runs continuously; we only collect candidates until the hold completes.
    private func accumulateFrame(_ jpeg: Data) {
        guard isPerceiving, !analysisCompletedForHold else { return }
        frameSelector.consider(jpeg)
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
                self?.analyzeSelectedFrameOnce()
                self?.tryRevealPendingObservation()
            }
        }
    }

    /// One analysis per completed eye hold — after the ring fills and one good frame is chosen.
    private func analyzeSelectedFrameOnce() {
        guard isPerceiving, !analysisCompletedForHold else { return }

        analysisTask?.cancel()
        analysisTask = Task { [weak self] in
            await self?.runSingleHoldAnalysis()
        }
    }

    private func runSingleHoldAnalysis() async {
        guard isPerceiving, !analysisCompletedForHold else { return }

        guard let sourceJPEG = frameSelector.selectedJPEG() else {
            analysisCompletedForHold = true
            return
        }

        let quality = FrameQuality.assess(sourceJPEG)
        guard quality.isAcceptable else {
            analysisCompletedForHold = true
            return
        }

        let profile = PerceptionConfiguration.curiosityProfile
        let anchor = await subjectIdentifier.estimateAnchor(jpeg: sourceJPEG) ?? CGPoint(x: 0.5, y: 0.5)

        guard let prepared = FramePreparation.prepare(sourceJPEG: sourceJPEG, anchor: anchor) else {
            analysisCompletedForHold = true
            return
        }

        let cameraMetadata = Self.cameraMetadata(for: prepared.sourceJPEG)
        var identity: SubjectIdentity?
        var comparisonStrategy: ComparisonStrategy?
        let result: AnalysisResult

        if let resolution = await subjectIdentifier.identify(jpeg: prepared.analysisJPEG, profile: profile) {
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
                comparisonJPEG = await observationStore.analysisJPEG(for: comparison.record)
            }

            let needsAPI = !PerceptionConfiguration.useDemoPerception
                && (!hasBaseline || (comparison != nil && !isSameSession))

            if needsAPI {
                let budget = await requestBudget.canRequest(entityID: entity.id)
                if !budget.allowed {
                    analysisCompletedForHold = true
                    return
                }
            }

            result = await continuityService.perceive(
                preparedFrame: prepared,
                identity: identity!,
                comparison: comparison,
                comparisonJPEG: comparisonJPEG,
                hasBaseline: hasBaseline,
                isSameSession: isSameSession,
                useDemoFirstVisit: PerceptionConfiguration.useDemoPerception
            )

            if needsAPI, case .observation = result.outcome {
                await requestBudget.recordRequest(
                    stage: hasBaseline ? .continuityComparison : .firstObservation,
                    entityID: entity.id,
                    analysisImageBytes: prepared.analysisJPEG.count
                )
            } else if needsAPI, case .silent(let reason) = result.outcome, reason == .noMeaningfulChange {
                await requestBudget.recordRequest(
                    stage: .continuityComparison,
                    entityID: entity.id,
                    analysisImageBytes: prepared.analysisJPEG.count
                )
            }
        } else if PerceptionConfiguration.useDemoPerception {
            analysisCompletedForHold = true
            return
        } else {
            let budget = await requestBudget.canRequest(entityID: nil)
            guard budget.allowed else {
                analysisCompletedForHold = true
                return
            }

            do {
                result = try await analysisService.analyze(jpeg: prepared.analysisJPEG)
                await requestBudget.recordRequest(
                    stage: .firstObservation,
                    entityID: nil,
                    analysisImageBytes: prepared.analysisJPEG.count
                )
            } catch {
                result = Self.failureResult(for: error)
            }
        }

        guard isPerceiving else { return }
        analysisCompletedForHold = true

        await persistIfNeeded(
            preparedFrame: prepared,
            identity: identity,
            result: result,
            cameraMetadata: cameraMetadata,
            comparisonStrategy: comparisonStrategy
        )

        apply(result)
        tryRevealPendingObservation()
    }

    private func persistIfNeeded(
        preparedFrame: PreparedFrame,
        identity: SubjectIdentity?,
        result: AnalysisResult,
        cameraMetadata: CameraCaptureMetadata?,
        comparisonStrategy: ComparisonStrategy?
    ) async {
        switch result.outcome {
        case .observation:
            if let entityID = identity?.persistentEntityID {
                _ = try? await observationStore.save(
                    preparedFrame: preparedFrame,
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
                    preparedFrame: preparedFrame,
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
                    preparedFrame: preparedFrame,
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
        case .silent:
            break
        }
    }

    private static func isSameSession(entityID: UUID, lastInspectionByEntity: [UUID: Date]) -> Bool {
        guard let last = lastInspectionByEntity[entityID] else { return false }
        return Date().timeIntervalSince(last) < PerceptionConfiguration.continuityRevisitInterval
    }

    private static func failureResult(for error: Error) -> AnalysisResult {
        if error is URLError {
            return .silent(.networkFailure, rawResponse: "network:\(error.localizedDescription)")
        }
        return .silent(.modelFailure, rawResponse: "model:\(error.localizedDescription)")
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

            await MainActor.run { self?.displayedObservation = nil }

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
