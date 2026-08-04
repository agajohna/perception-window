//
//  PerceptionState.swift
//  Perception Window
//
//  Unified sensor-fused state for Glass View reprojection.
//

import ARKit
import CoreVideo
import simd

#if os(iOS)

// MARK: - Fallback

enum GlassViewFallbackMode: String, Sendable {
    case fullReprojection
    case simplifiedReprojection
    case passthrough
}

// MARK: - Viewer pose

struct ViewerPoseEstimate: Sendable {
    var eyeMidpointDevice: SIMD3<Float>
    var eyeToScreenDistanceMeters: Float
    var lateralOffsetMeters: SIMD2<Float>
    var confidence: Float
    var isValid: Bool
    var timestamp: TimeInterval

    static let invalid = ViewerPoseEstimate(
        eyeMidpointDevice: .zero,
        eyeToScreenDistanceMeters: PerceptionConfiguration.virtualEyeDistanceMeters,
        lateralOffsetMeters: .zero,
        confidence: 0,
        isValid: false,
        timestamp: 0
    )
}

// MARK: - Scene depth

struct SceneDepthEstimate: Sendable {
    var dominantPlaneDepthMeters: Float
    var planeNormal: SIMD3<Float>
    var confidence: Float
    var source: Source

    enum Source: String, Sendable {
        case fixed
        case parallax
        case featurePoints
        case arPlane
        case fused
    }

    static func fixed(_ depth: Float, normal: SIMD3<Float>) -> SceneDepthEstimate {
        SceneDepthEstimate(
            dominantPlaneDepthMeters: depth,
            planeNormal: normal,
            confidence: 0.25,
            source: .fixed
        )
    }
}

// MARK: - Camera intrinsics

struct CameraIntrinsics: Sendable {
    var focalLength: SIMD2<Float>
    var principalPoint: SIMD2<Float>
    var imageResolution: SIMD2<Float>
    var captureDeviceType: String

    static func make(from camera: ARCamera, imageResolution: CGSize) -> CameraIntrinsics {
        let intrinsics = camera.intrinsics
        return CameraIntrinsics(
            focalLength: SIMD2(intrinsics[0][0], intrinsics[1][1]),
            principalPoint: SIMD2(intrinsics[2][0], intrinsics[2][1]),
            imageResolution: SIMD2(Float(imageResolution.width), Float(imageResolution.height)),
            captureDeviceType: "wide"
        )
    }

    static func make(from frame: ARFrame) -> CameraIntrinsics {
        let resolution = CGSize(
            width: CVPixelBufferGetWidth(frame.capturedImage),
            height: CVPixelBufferGetHeight(frame.capturedImage)
        )
        let intrinsics = frame.camera.intrinsics
        return CameraIntrinsics(
            focalLength: SIMD2(intrinsics[0][0], intrinsics[1][1]),
            principalPoint: SIMD2(intrinsics[2][0], intrinsics[2][1]),
            imageResolution: SIMD2(Float(resolution.width), Float(resolution.height)),
            captureDeviceType: "wide"
        )
    }
}

// MARK: - Rear textures

struct RearCameraTextures: Sendable {
    var widePixelBuffer: CVPixelBuffer?
    var ultraWidePixelBuffer: CVPixelBuffer?
    var activeSources: ActiveSources
    var timestamp: TimeInterval

    struct ActiveSources: OptionSet, Sendable {
        let rawValue: Int
        static let wide = ActiveSources(rawValue: 1 << 0)
        static let ultraWide = ActiveSources(rawValue: 1 << 1)
    }

    static let empty = RearCameraTextures(
        widePixelBuffer: nil,
        ultraWidePixelBuffer: nil,
        activeSources: [],
        timestamp: 0
    )
}

// MARK: - Confidence

struct PerceptionConfidence: Sendable {
    var overall: Float
    var viewerPose: Float
    var sceneDepth: Float
    var deviceTracking: Float
    var rearTextures: Float

    var supportsFullReprojection: Bool {
        overall >= PerceptionConfiguration.glassViewFullReprojectionThreshold
    }

    var supportsSimplifiedReprojection: Bool {
        overall >= PerceptionConfiguration.glassViewSimplifiedReprojectionThreshold
    }

    static let zero = PerceptionConfidence(
        overall: 0,
        viewerPose: 0,
        sceneDepth: 0,
        deviceTracking: 0,
        rearTextures: 0
    )
}

// MARK: - Unified state

struct PerceptionState: Sendable {
    var viewerPose: ViewerPoseEstimate
    var devicePose: simd_float4x4
    var predictedDevicePose: simd_float4x4
    var sceneDepth: SceneDepthEstimate
    var rearCameraIntrinsics: CameraIntrinsics
    var availableRearTextures: RearCameraTextures
    var confidence: PerceptionConfidence
    var fallbackMode: GlassViewFallbackMode
    var timestamp: TimeInterval
    var frameIndex: UInt64

    static let initial = PerceptionState(
        viewerPose: .invalid,
        devicePose: matrix_identity_float4x4,
        predictedDevicePose: matrix_identity_float4x4,
        sceneDepth: .fixed(PerceptionConfiguration.scenePlaneDepthMeters, normal: SIMD3(0, 0, -1)),
        rearCameraIntrinsics: CameraIntrinsics(
            focalLength: .zero,
            principalPoint: .zero,
            imageResolution: .zero,
            captureDeviceType: "unknown"
        ),
        availableRearTextures: .empty,
        confidence: .zero,
        fallbackMode: .passthrough,
        timestamp: 0,
        frameIndex: 0
    )
}

// MARK: - Warp policy

enum GlassViewWarpPolicy {
    struct Decision: Sendable {
        var active: Bool
        var reason: String
    }

    static func evaluate(
        state: PerceptionState,
        reference: VirtualEyeGeometry.SceneReference?
    ) -> Decision {
        if PerceptionConfiguration.glassViewForcePassthroughPreview {
            return Decision(active: false, reason: "force passthrough")
        }
        guard reference != nil else {
            return Decision(active: false, reason: "no scene reference")
        }
        guard state.frameIndex > 0 else {
            return Decision(active: false, reason: "fusion not started")
        }

        switch state.fallbackMode {
        case .passthrough:
            return Decision(active: false, reason: "fallback passthrough")
        case .fullReprojection, .simplifiedReprojection:
            break
        }

        let depth = state.sceneDepth.dominantPlaneDepthMeters
        if depth < PerceptionConfiguration.scenePlaneDepthMinimumMeters {
            return Decision(active: false, reason: "depth too close")
        }
        if depth > PerceptionConfiguration.scenePlaneDepthMaximumMeters {
            return Decision(active: false, reason: "depth too far")
        }
        if state.confidence.deviceTracking < 0.15 {
            return Decision(active: false, reason: "tracking unavailable")
        }

        return Decision(active: true, reason: state.fallbackMode.rawValue)
    }
}

#endif
