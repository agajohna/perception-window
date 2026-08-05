//
//  PerceptionStateFusion.swift
//  Perception Window
//
//  Fuses TrueDepth viewer pose, ARKit device pose, IMU prediction, scene depth,
//  and rear camera textures into a unified PerceptionState.
//

import ARKit
import CoreVideo
import UIKit

#if os(iOS)

final class PerceptionStateFusion {
    private let viewerTracker = ViewerPoseTracker()
    private let arKitFaceTracker = ARKitFaceViewerTracker()
    private let imuBridge = IMUPoseBridge()
    private let sceneDepthFusion = SceneDepthFusion()

    private var frameIndex: UInt64 = 0
    private var depthPrimed = false
    private var lastReprojectionError: Float = 0
    private var lockedPlaneAnchor: SIMD3<Float>?
    private var lockedVirtualEyeWorld: SIMD3<Float>?
    private var lockedPlaneNormal: SIMD3<Float>?

    func start() {
        imuBridge.start()
        arKitFaceTracker.reset()
        viewerTracker.start()
    }

    func ingestFaceAnchor(_ anchor: ARFaceAnchor, frame: ARFrame) {
        guard ARKitFaceViewerTracker.isSupported else { return }
        arKitFaceTracker.ingest(faceAnchor: anchor, frame: frame)
    }

    func stop() {
        imuBridge.stop()
        viewerTracker.stop()
        depthPrimed = false
        frameIndex = 0
        lockedPlaneAnchor = nil
        lockedVirtualEyeWorld = nil
        lockedPlaneNormal = nil
    }

    func resetDepth(from snapshot: ARFrameSnapshot) {
        sceneDepthFusion.reset(from: snapshot)
        depthPrimed = true
    }

    func resetAll() {
        sceneDepthFusion.resetToDefaults()
        depthPrimed = false
        frameIndex = 0
        lockedPlaneAnchor = nil
        lockedVirtualEyeWorld = nil
        lockedPlaneNormal = nil
    }

    func forceLock(from transform: simd_float4x4) {
        let profile = DeviceOpticalProfile.current
        let eyeLocal = profile.virtualEyeOffsetFromCamera(
            eyeDistanceMeters: PerceptionConfiguration.virtualEyeDistanceMeters
        )
        lockedPlaneAnchor = transform.position
        lockedVirtualEyeWorld = transform.transformPoint(eyeLocal)
        lockedPlaneNormal = transform.forward
    }

    func sceneReference(
        from state: PerceptionState,
        snapshot: ARFrameSnapshot
    ) -> VirtualEyeGeometry.SceneReference {
        let deviceTransform = state.predictedDevicePose
        if lockedPlaneAnchor == nil {
            let profile = DeviceOpticalProfile.current
            let eyeLocal = profile.virtualEyeOffsetFromCamera(
                eyeDistanceMeters: PerceptionConfiguration.virtualEyeDistanceMeters
            )
            lockedPlaneAnchor = deviceTransform.position
            lockedVirtualEyeWorld = deviceTransform.transformPoint(eyeLocal)
            lockedPlaneNormal = deviceTransform.forward
        }
        return VirtualEyeGeometry.sceneReference(
            from: state,
            snapshot: snapshot,
            lockedPlaneAnchor: lockedPlaneAnchor!,
            lockedVirtualEyeWorld: lockedVirtualEyeWorld!,
            lockedPlaneNormal: lockedPlaneNormal!
        )
    }

    func liveViewerPose() -> ViewerPoseEstimate {
        let diag = resolvedViewerDiagnostics()
        var pose = diag.estimate
        if diag.secondsSinceFrame < 0 || diag.secondsSinceFrame > 0.55 {
            pose = .invalid
        }
        return pose
    }

    func update(from input: ARFrameFusionInput) -> PerceptionState {
        frameIndex &+= 1

        imuBridge.ingestARKitTransform(input.snapshot.cameraTransform, timestamp: input.timestamp)
        let (predictedPose, imuApplied) = imuBridge.predictedTransform()

        if !depthPrimed {
            sceneDepthFusion.reset(from: input.snapshot)
            depthPrimed = true
        }

        let sceneDepth = sceneDepthFusion.update(from: input)

        let viewerDiag = resolvedViewerDiagnostics()
        var viewerPose = viewerDiag.estimate
        if viewerDiag.secondsSinceFrame < 0 || viewerDiag.secondsSinceFrame > 0.55 {
            viewerPose = .invalid
        }

        let trackingConfidence = trackingConfidence(for: input.trackingState)

        var activeSources: RearCameraTextures.ActiveSources = []
        activeSources.insert(.wide)

        let textures = RearCameraTextures(
            widePixelBuffer: input.copiedWideBuffer,
            ultraWidePixelBuffer: nil,
            activeSources: activeSources,
            timestamp: input.timestamp
        )

        let rearConfidence: Float = 0.9
        let viewerConfidence = viewerPose.isValid ? viewerPose.confidence : 0
        let depthConfidence = sceneDepth.confidence

        let overall = weightedConfidence(
            viewer: viewerConfidence,
            depth: depthConfidence,
            tracking: trackingConfidence,
            rear: rearConfidence
        )

        let fallbackMode = resolveFallbackMode(
            overall: overall,
            tracking: trackingConfidence,
            rear: rearConfidence
        )

        lastReprojectionError = estimateReprojectionError(
            viewerPose: viewerPose,
            sceneDepth: sceneDepth,
            trackingConfidence: trackingConfidence
        )

        return PerceptionState(
            viewerPose: viewerPose,
            devicePose: input.snapshot.cameraTransform,
            predictedDevicePose: imuApplied ? predictedPose : input.snapshot.cameraTransform,
            sceneDepth: sceneDepth,
            rearCameraIntrinsics: input.intrinsics,
            availableRearTextures: textures,
            confidence: PerceptionConfidence(
                overall: overall,
                viewerPose: viewerConfidence,
                sceneDepth: depthConfidence,
                deviceTracking: trackingConfidence,
                rearTextures: rearConfidence
            ),
            fallbackMode: fallbackMode,
            timestamp: input.timestamp,
            frameIndex: frameIndex
        )
    }

    func makeDebugMetrics(
        from state: PerceptionState,
        renderLatencyMs: Double,
        trackingState: ARCamera.TrackingState,
        imuApplied: Bool
    ) -> GlassViewDebugMetrics {
        var sources: [String] = []
        if state.availableRearTextures.activeSources.contains(.wide) { sources.append("wide") }
        if state.availableRearTextures.activeSources.contains(.ultraWide) { sources.append("ultraWide") }

        let viewerDiag = resolvedViewerDiagnostics()
        let lastFrameMs = viewerDiag.secondsSinceFrame >= 0 ? viewerDiag.secondsSinceFrame * 1000 : -1

        return GlassViewDebugMetrics(
            viewerPoseConfidence: state.confidence.viewerPose,
            estimatedEyeDistanceMeters: state.viewerPose.eyeToScreenDistanceMeters,
            estimatedSceneDepthMeters: state.sceneDepth.dominantPlaneDepthMeters,
            sceneDepthSource: state.sceneDepth.source.rawValue,
            activeRearCameraSources: sources.isEmpty ? "none" : sources.joined(separator: "+"),
            reprojectionErrorEstimate: lastReprojectionError,
            fallbackMode: state.fallbackMode.rawValue,
            thermalState: thermalLabel,
            renderLatencyMs: renderLatencyMs,
            frameIndex: state.frameIndex,
            deviceTrackingState: trackingLabel(for: trackingState),
            imuPredictionApplied: imuApplied,
            viewerTrackerStatus: viewerDiag.status.rawValue + viewerDiag.sourceTag,
            viewerFramesReceived: viewerDiag.framesReceived,
            viewerFacesDetected: viewerDiag.facesDetected,
            viewerLastFrameMs: lastFrameMs,
            eyeSource: state.viewerPose.isValid ? "live" : "fixed"
        )
    }

    private var thermalLabel: String {
        switch ProcessInfo.processInfo.thermalState {
        case .nominal: return "nominal"
        case .fair: return "fair"
        case .serious: return "serious"
        case .critical: return "critical"
        @unknown default: return "unknown"
        }
    }

    private func trackingConfidence(for state: ARCamera.TrackingState) -> Float {
        switch state {
        case .normal:
            return 1
        case .limited(let reason):
            switch reason {
            case .initializing, .relocalizing:
                return 0.35
            case .excessiveMotion, .insufficientFeatures:
                return 0.2
            @unknown default:
                return 0.25
            }
        case .notAvailable:
            return 0
        }
    }

    private func trackingLabel(for state: ARCamera.TrackingState) -> String {
        switch state {
        case .normal:
            return "normal"
        case .limited(let reason):
            return "limited(\(reason))"
        case .notAvailable:
            return "notAvailable"
        }
    }

    private func weightedConfidence(
        viewer: Float,
        depth: Float,
        tracking: Float,
        rear: Float
    ) -> Float {
        let viewerWeight: Float = PerceptionConfiguration.glassViewViewerPoseEnabled ? 0.25 : 0
        let depthWeight: Float = 0.25
        let trackingWeight: Float = 0.35
        let rearWeight: Float = 0.15
        let totalWeight = viewerWeight + depthWeight + trackingWeight + rearWeight
        guard totalWeight > 0 else { return 0 }

        return (
            viewer * viewerWeight
                + depth * depthWeight
                + tracking * trackingWeight
                + rear * rearWeight
        ) / totalWeight
    }

    private func resolveFallbackMode(overall: Float, tracking: Float, rear: Float) -> GlassViewFallbackMode {
        if tracking < 0.05 || rear < 0.1 {
            return .passthrough
        }
        // Keep warp alive through brief tracking hiccups (fast head motion).
        if tracking < 0.15 {
            return .simplifiedReprojection
        }
        // Without TrueDepth, simplified warp is always acceptable once tracking is live.
        if !PerceptionConfiguration.glassViewViewerPoseEnabled {
            return overall >= PerceptionConfiguration.glassViewSimplifiedReprojectionThreshold
                ? .simplifiedReprojection
                : .passthrough
        }
        if overall >= PerceptionConfiguration.glassViewFullReprojectionThreshold {
            return .fullReprojection
        }
        if overall >= PerceptionConfiguration.glassViewSimplifiedReprojectionThreshold {
            return .simplifiedReprojection
        }
        return .passthrough
    }

    private func estimateReprojectionError(
        viewerPose: ViewerPoseEstimate,
        sceneDepth: SceneDepthEstimate,
        trackingConfidence: Float
    ) -> Float {
        var error: Float = 0

        if !viewerPose.isValid {
            error += 0.35
        } else {
            error += (1 - viewerPose.confidence) * 0.2
        }

        error += (1 - sceneDepth.confidence) * 0.25
        error += (1 - trackingConfidence) * 0.3

        let depthDelta = abs(sceneDepth.dominantPlaneDepthMeters - PerceptionConfiguration.scenePlaneDepthMeters)
        error += min(depthDelta * 0.08, 0.2)

        return min(error, 1)
    }

    private func resolvedViewerDiagnostics() -> (
        estimate: ViewerPoseEstimate,
        status: ViewerTrackerStatus,
        framesReceived: UInt64,
        facesDetected: UInt64,
        secondsSinceFrame: TimeInterval,
        sourceTag: String
    ) {
        if ARKitFaceViewerTracker.isSupported {
            let diag = arKitFaceTracker.diagnosticSnapshot()
            return (
                arKitFaceTracker.currentEstimate(),
                diag.status,
                diag.framesReceived,
                diag.facesDetected,
                diag.secondsSinceFrame,
                "+arkit"
            )
        }

        let diag = viewerTracker.diagnosticSnapshot()
        return (
            viewerTracker.currentEstimate(),
            diag.status,
            diag.framesReceived,
            diag.facesDetected,
            diag.secondsSinceFrame,
            diag.usesMultiCam ? "+mc" : "+av"
        )
    }
}

#endif
