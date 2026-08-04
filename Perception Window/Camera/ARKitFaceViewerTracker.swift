//
//  ARKitFaceViewerTracker.swift
//  Perception Window
//
//  User face pose via ARWorldTrackingConfiguration.userFaceTrackingEnabled.
//  Avoids a separate AVCaptureSession that conflicts with ARKit on iPhone 12 mini.
//

import ARKit
import simd

#if os(iOS)

final class ARKitFaceViewerTracker {
    private let lock = NSLock()
    private var latestEstimate = ViewerPoseEstimate.invalid
    private var status: ViewerTrackerStatus = .stopped
    private var lastFrameTime: TimeInterval = 0
    private var framesReceived: UInt64 = 0
    private var facesDetected: UInt64 = 0

    static var isSupported: Bool {
        PerceptionConfiguration.glassViewViewerPoseEnabled
            && ARWorldTrackingConfiguration.supportsUserFaceTracking
    }

    func reset() {
        lock.lock()
        latestEstimate = .invalid
        status = Self.isSupported ? .starting : .stopped
        lastFrameTime = 0
        framesReceived = 0
        facesDetected = 0
        lock.unlock()
    }

    func ingest(faceAnchor: ARFaceAnchor, frame: ARFrame) {
        let now = CACurrentMediaTime()
        let deviceTransform = frame.camera.transform
        let deviceInverse = deviceTransform.inverse

        let leftEyeWorld = faceAnchor.transform * faceAnchor.leftEyeTransform
        let rightEyeWorld = faceAnchor.transform * faceAnchor.rightEyeTransform
        let eyeMidWorld = SIMD3<Float>(
            (leftEyeWorld.columns.3.x + rightEyeWorld.columns.3.x) * 0.5,
            (leftEyeWorld.columns.3.y + rightEyeWorld.columns.3.y) * 0.5,
            (leftEyeWorld.columns.3.z + rightEyeWorld.columns.3.z) * 0.5
        )

        let eyeMidDevice = deviceInverse.transformPoint(eyeMidWorld)
        let eyeLocal = eyeMidDevice

        let profile = DeviceOpticalProfile.current
        let eyeDistance = min(max(abs(eyeLocal.z), 0.30), 0.65)
        let lateral = SIMD2(eyeLocal.x, eyeLocal.y)
        let gain = PerceptionConfiguration.viewerPoseLateralGain
        let adjustedEye = profile.virtualEyeOffsetFromCamera(eyeDistanceMeters: eyeDistance)
            + SIMD3(lateral.x * gain, lateral.y * gain, 0)

        let estimate = ViewerPoseEstimate(
            eyeMidpointDevice: adjustedEye,
            eyeToScreenDistanceMeters: eyeDistance,
            lateralOffsetMeters: lateral,
            confidence: faceAnchor.isTracked ? 0.95 : 0.6,
            isValid: true,
            timestamp: now
        )

        lock.lock()
        latestEstimate = estimate
        framesReceived &+= 1
        facesDetected &+= 1
        lastFrameTime = now
        status = .active
        lock.unlock()
    }

    func currentEstimate() -> ViewerPoseEstimate {
        lock.lock()
        defer { lock.unlock() }

        guard latestEstimate.isValid else { return .invalid }

        let staleAfter = 0.55
        if lastFrameTime == 0 || CACurrentMediaTime() - lastFrameTime > staleAfter {
            return .invalid
        }

        return latestEstimate
    }

    func diagnosticSnapshot() -> (
        status: ViewerTrackerStatus,
        framesReceived: UInt64,
        facesDetected: UInt64,
        secondsSinceFrame: TimeInterval,
        usesMultiCam: Bool
    ) {
        lock.lock()
        defer { lock.unlock() }
        let since = lastFrameTime > 0 ? CACurrentMediaTime() - lastFrameTime : -1
        return (status, framesReceived, facesDetected, since, false)
    }
}

#endif
