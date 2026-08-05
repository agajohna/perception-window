//
//  TransparentWindowSession.swift
//  Perception Window
//

import ARKit
import AVFoundation
import CoreVideo
import Foundation
import Observation
import UIKit

#if os(iOS)

@Observable
final class TransparentWindowSession: NSObject {
    enum AuthorizationState {
        case unknown
        case authorized
        case denied
    }

    let arSession = ARSession()

    private(set) var authorizationState: AuthorizationState = .unknown
    private(set) var isRunning = false

    @ObservationIgnored private(set) var sceneReference: VirtualEyeGeometry.SceneReference?
    @ObservationIgnored private(set) var perceptionState: PerceptionState = .initial
    @ObservationIgnored var warpPreviewEnabled = true
    @ObservationIgnored private(set) var lockedCameraWorldPosition: SIMD3<Float>?
    @ObservationIgnored private(set) var lockedViewerLateral: SIMD2<Float>?
    @ObservationIgnored private(set) var warpLockBaselineDeltas: [SIMD2<Float>]?
    @ObservationIgnored private(set) var debugMetrics: GlassViewDebugMetrics = .empty

    private let fusionLock = NSLock()
    private let fusionQueue = DispatchQueue(label: "glassview.fusion", qos: .userInteractive)
    private let renderPacketLock = NSLock()
    private nonisolated(unsafe) var latestRenderPacket: RenderFramePacket?
    private nonisolated(unsafe) var fusionJobPending = false

    /// When false, the ARSession delegate skips analysis frame relay (saves GPU/memory).
    var deliversAnalysisFrames = false {
        didSet { deliversAnalysisFramesFlag = deliversAnalysisFrames }
    }

    private nonisolated(unsafe) var deliversAnalysisFramesFlag = false

    nonisolated(unsafe) var onFrame: (@Sendable (CMSampleBuffer) -> Void)?

    private let frameRelay = ARFrameRelay()
    private let referenceLock = NSLock()
    private nonisolated(unsafe) var lockedSceneReference: VirtualEyeGeometry.SceneReference?
    private let depthEstimator = PlaneDepthEstimator(
        initialDepthMeters: PerceptionConfiguration.scenePlaneDepthMeters
    )
    private let perceptionFusion = PerceptionStateFusion()
    private let debugRecorder = GlassViewDebugRecorder()
    private nonisolated(unsafe) var fusionViewportSize: CGSize = UIScreen.main.nativeBounds.size
    private nonisolated(unsafe) var lastFusionTime: TimeInterval = 0

    var effectiveSceneReference: VirtualEyeGeometry.SceneReference? {
        fusionLock.lock()
        defer { fusionLock.unlock() }

        if PerceptionConfiguration.glassViewSensorFusionEnabled {
            return sceneReference
        }
        guard let sceneReference else { return nil }
        return VirtualEyeGeometry.referenceByUpdatingDepth(
            sceneReference,
            sceneDepthMeters: depthEstimator.sceneDepthMeters
        )
    }

    var usesSensorFusion: Bool {
        PerceptionConfiguration.glassViewSensorFusionEnabled
    }

    func setFusionViewportSize(_ size: CGSize) {
        guard size.width > 0, size.height > 0 else { return }
        fusionViewportSize = size
    }

    func currentPerceptionState() -> PerceptionState {
        fusionLock.lock()
        defer { fusionLock.unlock() }
        return perceptionState
    }

    func liveViewerPose() -> ViewerPoseEstimate {
        perceptionFusion.liveViewerPose()
    }

    func consumeLatestRenderPacket() -> RenderFramePacket? {
        renderPacketLock.lock()
        defer { renderPacketLock.unlock() }
        return latestRenderPacket
    }

    /// Metal render source — always matches the MTKView drawable viewport.
    func renderFrame(for viewportSize: CGSize) -> RenderFramePacket? {
        guard viewportSize.width > 1, viewportSize.height > 1 else { return nil }

        renderPacketLock.lock()
        let queuedBuffer = latestRenderPacket?.pixelBuffer
        renderPacketLock.unlock()

        guard let frame = arSession.currentFrame else { return nil }

        let pixelBuffer: CVPixelBuffer
        if let queuedBuffer {
            pixelBuffer = queuedBuffer
        } else if let copied = PixelBufferCopier.copy(frame.capturedImage) {
            pixelBuffer = copied
        } else {
            return nil
        }

        return RenderFramePacket(
            pixelBuffer: pixelBuffer,
            snapshot: ARFrameSnapshot.make(from: frame, viewportSize: viewportSize),
            timestamp: frame.timestamp
        )
    }

    func recordDrawFailure(_ reason: String) {
        fusionLock.lock()
        debugMetrics.lastDrawFailure = reason
        debugMetrics.renderMode = "waiting"
        fusionLock.unlock()
    }

    func applyFusionInput(_ input: ARFrameFusionInput) {
        guard usesSensorFusion else { return }

        let state = perceptionFusion.update(from: input)
        let reference = perceptionFusion.sceneReference(from: state, snapshot: input.snapshot)
        let imuApplied = state.predictedDevicePose != state.devicePose
        var metrics = perceptionFusion.makeDebugMetrics(
            from: state,
            renderLatencyMs: 0,
            trackingState: input.trackingState,
            imuApplied: imuApplied
        )

        fusionLock.lock()
        perceptionState = state
        sceneReference = reference
        if lockedCameraWorldPosition == nil {
            lockedCameraWorldPosition = input.snapshot.cameraTransform.position
        }
        if lockedViewerLateral == nil, state.viewerPose.isValid {
            lockedViewerLateral = state.viewerPose.lateralOffsetMeters
        }
        if !PerceptionConfiguration.glassViewUsePlanarMotionWarp, warpLockBaselineDeltas == nil {
            captureWarpLockBaseline(from: input.snapshot, reference: reference)
        }
        let warpDecision = GlassViewWarpPolicy.evaluate(state: state, reference: reference)
        metrics.warpActive = warpDecision.active
        metrics.warpBlockReason = warpDecision.reason
        metrics.warpExaggerationGain = PerceptionConfiguration.glassViewWarpExaggerationGain
        debugMetrics = metrics
        fusionLock.unlock()

        debugRecorder.record(metrics)
    }

    func updatePlaneDepth(from snapshot: ARFrameSnapshot) {
        depthEstimator.update(from: snapshot)
    }

    func resetDepthEstimator(from snapshot: ARFrameSnapshot) {
        depthEstimator.reset(
            from: snapshot,
            initialDepthMeters: PerceptionConfiguration.scenePlaneDepthMeters
        )
    }

    func prepare() async {
        let granted = await requestAccess()
        authorizationState = granted ? .authorized : .denied
        guard granted else { return }

        arSession.delegate = self
        if usesSensorFusion {
            perceptionFusion.start()
        }
        start()
    }

    func start() {
        let configuration = makeConfiguration()
        arSession.run(configuration, options: [.resetTracking, .removeExistingAnchors])
        isRunning = true
    }

    func stop() {
        arSession.pause()
        arSession.delegate = nil
        isRunning = false
        referenceLock.lock()
        lockedSceneReference = nil
        referenceLock.unlock()
        fusionLock.lock()
        sceneReference = nil
        lockedCameraWorldPosition = nil
        lockedViewerLateral = nil
        warpLockBaselineDeltas = nil
        perceptionState = .initial
        debugMetrics = .empty
        fusionLock.unlock()
        perceptionFusion.stop()
    }

    func recenterVirtualEye() {
        referenceLock.lock()
        lockedSceneReference = nil
        referenceLock.unlock()
        sceneReference = nil
        warpLockBaselineDeltas = nil
        lockedViewerLateral = nil
        depthEstimator.resetToInitialDepth(PerceptionConfiguration.scenePlaneDepthMeters)
        perceptionFusion.resetAll()

        if let frame = arSession.currentFrame {
            let viewport = fusionViewportSize.width > 1 && fusionViewportSize.height > 1
                ? fusionViewportSize
                : UIScreen.main.bounds.size
            let snapshot = ARFrameSnapshot.make(from: frame, viewportSize: viewport)
            perceptionFusion.forceLock(from: frame.camera.transform)
            lockedCameraWorldPosition = frame.camera.transform.position
            fusionLock.lock()
            let lockedReference = perceptionFusion.sceneReference(
                from: perceptionState.frameIndex > 0 ? perceptionState : makeBootstrapState(from: frame),
                snapshot: snapshot
            )
            sceneReference = lockedReference
            fusionLock.unlock()
            perceptionFusion.resetDepth(from: snapshot)
            captureWarpLockBaseline(from: snapshot, reference: lockedReference)
            fusionLock.lock()
            let liveViewer = perceptionFusion.liveViewerPose()
            if liveViewer.isValid {
                lockedViewerLateral = liveViewer.lateralOffsetMeters
            } else if perceptionState.viewerPose.isValid {
                lockedViewerLateral = perceptionState.viewerPose.lateralOffsetMeters
            }
            fusionLock.unlock()
        } else {
            lockedCameraWorldPosition = nil
        }

        fusionLock.lock()
        if perceptionState.frameIndex == 0 {
            perceptionState = .initial
        }
        fusionLock.unlock()
    }

    private func makeBootstrapState(from frame: ARFrame) -> PerceptionState {
        var state = PerceptionState.initial
        state.devicePose = frame.camera.transform
        state.predictedDevicePose = frame.camera.transform
        state.frameIndex = 1
        state.fallbackMode = .simplifiedReprojection
        state.confidence.deviceTracking = 1
        return state
    }

    func toggleWarpPreview() {
        warpPreviewEnabled.toggle()
    }

    private func captureWarpLockBaseline(
        from snapshot: ARFrameSnapshot,
        reference: VirtualEyeGeometry.SceneReference
    ) {
        warpLockBaselineDeltas = VirtualEyeGeometry.captureReprojectionDeltas(
            snapshot: snapshot,
            reference: reference,
            gridSize: PerceptionConfiguration.transparentWindowGridSize
        )
    }

    func recordWarpDiagnostics(
        presented: Bool,
        failureReason: String?,
        renderMode: String,
        maxUVShiftPixels: Float,
        reprojectionHits: Int,
        gridPointCount: Int,
        cameraDeltaMeters: Float,
        windowMagnification: Float,
        staticAlignPixels: Float
    ) {
        fusionLock.lock()
        debugMetrics.renderMode = presented ? renderMode : (failureReason ?? "draw failed")
        debugMetrics.maxUVShiftPixels = maxUVShiftPixels
        debugMetrics.reprojectionHits = reprojectionHits
        debugMetrics.reprojectionGridPoints = gridPointCount
        debugMetrics.cameraDeltaMeters = cameraDeltaMeters
        debugMetrics.windowMagnification = windowMagnification
        debugMetrics.staticAlignPixels = staticAlignPixels
        debugMetrics.warpPreviewEnabled = warpPreviewEnabled
        debugMetrics.lastDrawFailure = failureReason ?? (presented ? "ok" : "unknown")
        fusionLock.unlock()
    }

    func attachFrameRelay(_ handler: @escaping @Sendable (CMSampleBuffer) -> Void) {
        onFrame = handler
        frameRelay.onSampleBuffer = handler
    }

    func relayCopiedPixelBuffer(_ pixelBuffer: CVPixelBuffer, timestamp: TimeInterval) {
        frameRelay.processCopiedBuffer(pixelBuffer, timestamp: timestamp)
    }

    private func makeConfiguration() -> ARWorldTrackingConfiguration {
        let configuration = ARWorldTrackingConfiguration()
        configuration.planeDetection = PerceptionConfiguration.glassViewPlaneDetectionEnabled
            ? [.horizontal, .vertical]
            : []
        configuration.frameSemantics = []
        configuration.environmentTexturing = .none

        if PerceptionConfiguration.preferUltraWideCapture {
            if let format = ARWorldTrackingConfiguration.supportedVideoFormats
                .filter({ $0.captureDeviceType == .builtInUltraWideCamera })
                .sorted(by: { $0.imageResolution.width > $1.imageResolution.width })
                .first {
                configuration.videoFormat = format
            }
        }

        if PerceptionConfiguration.glassViewViewerPoseEnabled,
           ARWorldTrackingConfiguration.supportsUserFaceTracking {
            configuration.userFaceTrackingEnabled = true
        }

        if PerceptionConfiguration.usesMetalReprojection,
           PerceptionConfiguration.glassViewSceneDepthSemanticsEnabled {
            if ARWorldTrackingConfiguration.supportsFrameSemantics(.smoothedSceneDepth) {
                configuration.frameSemantics.insert(.smoothedSceneDepth)
            } else if ARWorldTrackingConfiguration.supportsFrameSemantics(.sceneDepth) {
                configuration.frameSemantics.insert(.sceneDepth)
            }
        }

        return configuration
    }

    private func requestAccess() async -> Bool {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            return true
        case .notDetermined:
            return await AVCaptureDevice.requestAccess(for: .video)
        default:
            return false
        }
    }

    nonisolated private func publishReferenceIfNeeded(for frame: ARFrame) {
        guard PerceptionConfiguration.usesViewpointReprojection else { return }
        guard !PerceptionConfiguration.glassViewSensorFusionEnabled else { return }
        guard frame.camera.trackingState == .normal else { return }

        referenceLock.lock()
        let needsReference = lockedSceneReference == nil
        referenceLock.unlock()
        guard needsReference else { return }

        let reference = VirtualEyeGeometry.lockReference(from: frame)

        referenceLock.lock()
        if lockedSceneReference == nil {
            lockedSceneReference = reference
        }
        let published = lockedSceneReference
        referenceLock.unlock()

        guard let published else { return }

        Task { @MainActor in
            if self.sceneReference == nil {
                self.sceneReference = published
            }
        }
    }

    nonisolated private func ingestRenderPacket(from frame: ARFrame) {
        guard PerceptionConfiguration.usesViewpointReprojection else { return }

        let viewport = fusionViewportSize.width > 1 && fusionViewportSize.height > 1
            ? fusionViewportSize
            : UIScreen.main.nativeBounds.size

        guard let copied = PixelBufferCopier.copy(frame.capturedImage) else { return }

        let snapshot = ARFrameSnapshot.make(from: frame, viewportSize: viewport)
        let packet = RenderFramePacket(
            pixelBuffer: copied,
            snapshot: snapshot,
            timestamp: frame.timestamp
        )

        renderPacketLock.lock()
        latestRenderPacket = packet
        renderPacketLock.unlock()
    }

    nonisolated private func runFusionIfNeeded(for frame: ARFrame) {
        guard PerceptionConfiguration.glassViewSensorFusionEnabled else { return }
        guard PerceptionConfiguration.usesViewpointReprojection else { return }
        guard frame.camera.trackingState != .notAvailable else { return }

        let now = CACurrentMediaTime()
        let interval = 1.0 / PerceptionConfiguration.fusionProcessingRateHz
        guard now - lastFusionTime >= interval else { return }
        if fusionViewportSize.width <= 1 || fusionViewportSize.height <= 1 {
            fusionViewportSize = UIScreen.main.nativeBounds.size
        }
        guard !fusionJobPending else { return }
        fusionJobPending = true
        lastFusionTime = now

        guard let copied = PixelBufferCopier.copy(frame.capturedImage) else {
            fusionJobPending = false
            return
        }

        let input = ARFrameFusionInput.capture(
            from: frame,
            viewportSize: fusionViewportSize,
            copiedBuffer: copied
        )

        fusionQueue.async { [weak self] in
            defer { self?.fusionJobPending = false }
            self?.applyFusionInput(input)
        }
    }

    nonisolated private func relayCopiedAnalysisFrame(from frame: ARFrame) {
        guard deliversAnalysisFramesFlag else { return }
        guard let copied = PixelBufferCopier.copy(frame.capturedImage) else { return }
        frameRelay.processCopiedBuffer(copied, timestamp: frame.timestamp)
    }
}

extension TransparentWindowSession: ARSessionDelegate {
    nonisolated func session(_ session: ARSession, didUpdate frame: ARFrame) {
        ingestRenderPacket(from: frame)
        publishReferenceIfNeeded(for: frame)
        runFusionIfNeeded(for: frame)
        relayCopiedAnalysisFrame(from: frame)
    }

    nonisolated func session(_ session: ARSession, didUpdate anchors: [ARAnchor]) {
        guard PerceptionConfiguration.glassViewViewerPoseEnabled else { return }
        guard let frame = session.currentFrame else { return }

        for anchor in anchors {
            guard let faceAnchor = anchor as? ARFaceAnchor else { continue }
            perceptionFusion.ingestFaceAnchor(faceAnchor, frame: frame)
        }
    }

    nonisolated func session(_ session: ARSession, didFailWithError error: Error) {
        Task { @MainActor in
            self.isRunning = false
        }
    }
}

private final class ARFrameRelay: @unchecked Sendable {
    var onSampleBuffer: (@Sendable (CMSampleBuffer) -> Void)?

    private var lastCaptureTime: TimeInterval = 0
    private let lock = NSLock()

    func processCopiedBuffer(_ pixelBuffer: CVPixelBuffer, timestamp: TimeInterval) {
        let now = CACurrentMediaTime()

        lock.lock()
        defer { lock.unlock() }

        guard now - lastCaptureTime > 0.15 else { return }
        lastCaptureTime = now

        guard let sampleBuffer = SampleBufferFactory.make(from: pixelBuffer, timestamp: timestamp) else { return }
        onSampleBuffer?(sampleBuffer)
    }
}

private enum SampleBufferFactory {
    static func make(from pixelBuffer: CVPixelBuffer, timestamp: TimeInterval) -> CMSampleBuffer? {
        var formatDescription: CMFormatDescription?
        CMVideoFormatDescriptionCreateForImageBuffer(
            allocator: kCFAllocatorDefault,
            imageBuffer: pixelBuffer,
            formatDescriptionOut: &formatDescription
        )
        guard let formatDescription else { return nil }

        var timing = CMSampleTimingInfo(
            duration: .invalid,
            presentationTimeStamp: CMTime(seconds: timestamp, preferredTimescale: 1_000_000_000),
            decodeTimeStamp: .invalid
        )

        var sampleBuffer: CMSampleBuffer?
        CMSampleBufferCreateReadyWithImageBuffer(
            allocator: kCFAllocatorDefault,
            imageBuffer: pixelBuffer,
            formatDescription: formatDescription,
            sampleTiming: &timing,
            sampleBufferOut: &sampleBuffer
        )
        return sampleBuffer
    }
}

#else

@Observable
final class TransparentWindowSession {
    enum AuthorizationState {
        case unknown
        case authorized
        case denied
    }

    private(set) var authorizationState: AuthorizationState = .denied
    private(set) var isRunning = false

    var onFrame: (@Sendable (CMSampleBuffer) -> Void)?

    func prepare() async {}
    func start() {}
    func stop() {}
    func recenterVirtualEye() {}
    func attachFrameRelay(_ handler: @escaping @Sendable (CMSampleBuffer) -> Void) {}
    func relayCopiedPixelBuffer(_ pixelBuffer: CVPixelBuffer, timestamp: TimeInterval) {}
}

#endif
