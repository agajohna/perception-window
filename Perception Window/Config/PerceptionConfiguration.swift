//
//  PerceptionConfiguration.swift
//  Perception Window
//

import AVFoundation
import Foundation
import simd

#if canImport(CoreGraphics)
import CoreGraphics
#endif

enum PerceptionConfiguration {
    static let useDemoPerception = true

    /// Learned curiosity weights — internal, not user-facing modes.
    static var curiosityProfile: CuriosityProfile = .default

    /// Time for the eye ring to fill — perception coming into focus.
    static let focusFillDuration: TimeInterval = 1.0

    /// Pause between observations when attention moves.
    static let attentionTransitionPause: TimeInterval = 0.5

    static let observationFadeDuration: TimeInterval = 0.35

    /// Same entity within this window continues the current inspection — no continuity comparison.
    static let continuityRevisitInterval: TimeInterval = 120

    /// Cooldown before another API request for the same entity.
    static let requestCooldownInterval: TimeInterval = 120

    /// Minimum confidence to link a retrieval hint to an existing entity.
    static let subjectMatchThreshold: Float = 0.15

    // MARK: - API cost guardrails

    /// One analysis per completed eye hold — enforced by pipeline, not interval polling.
    static let dailyRequestCeiling: Int = 100
    static let maxAnalysisImageDimension: Int = 1024
    static let analysisJPEGQuality: CGFloat = 0.82
    static let maxResponseTokens: Int = 220

    // MARK: - On-device frame quality gates

    static let minimumSharpness: Float = 5
    static let minimumBrightness: Float = 0.08
    static let maximumBrightness: Float = 0.96

    // MARK: - Preview mode (staged transparent window)

    enum PreviewMode {
        /// Step 1 — proven AVCapture live feed.
        case avCapture
        /// Step 2 — ARKit world tracking + native ARSCNView passthrough.
        case arKitPassthrough
        /// Step 3 — ARKit + Metal viewpoint reprojection.
        case arKitReprojection
    }

    static let previewMode: PreviewMode = .arKitPassthrough

    /// Step 3 overlay — viewpoint warp on top of the Step 2 ARSCNView base.
    static let viewpointReprojectionOverlayEnabled = true

    static var usesAVCapturePreview: Bool { previewMode == .avCapture }
    static var usesARKitSession: Bool { previewMode != .avCapture }

    static var usesViewpointReprojection: Bool {
        switch previewMode {
        case .arKitReprojection:
            return true
        case .arKitPassthrough:
            return viewpointReprojectionOverlayEnabled
        case .avCapture:
            return false
        }
    }

    static var usesMetalReprojection: Bool { usesViewpointReprojection }

    /// When true, the product targets viewpoint-correct reprojection.
    static let useTransparentWindow = true

    /// Step 3 flag — prefer `viewpointReprojectionOverlayEnabled` on the passthrough base.
    static var transparentWindowReprojectionEnabled: Bool {
        usesViewpointReprojection
    }

    /// Legacy alias for Metal reprojection path.
    static var usesARKitPreview: Bool { usesMetalReprojection }

    /// Localized subject magnification during eye hold — disabled while tuning the base view.
    static let lensMagnificationEnabled = false

    // MARK: - Stage A1 calibration (tune separately)

    /// Hold phone still — tune until the seam aligns at your working distance.
    static var virtualEyeDistanceMeters: Float = 0.375

    /// Translate phone sideways — tune until the seam stays aligned.
    /// Baseline working distance: phone to subject (~60 cm for desk printer test).
    static var scenePlaneDepthMeters: Float = 0.6
    static let scenePlaneDepthMinimumMeters: Float = 0.35
    static let scenePlaneDepthMaximumMeters: Float = 4.0
    /// Fused depth outside this band is nudged back toward `scenePlaneDepthMeters`.
    static let sceneDepthPreferredMinimumMeters: Float = 0.45
    static let sceneDepthPreferredMaximumMeters: Float = 1.5

    /// Stage A2 — infer plane depth from small lateral motion.
    static let planeDepthLateralGain: Float = 0.35
    static let planeDepthMinLateralMotionMeters: Float = 0.008

    static let transparentWindowGridSize = 24

    static var preferUltraWideCapture: Bool {
        previewMode == .arKitReprojection
    }

    // MARK: - Glass View sensor fusion

    /// When true, Glass View uses fused PerceptionState instead of fixed A1 calibration.
    static let glassViewSensorFusionEnabled = true

    /// TrueDepth viewer pose — front camera face landmarks during Glass View.
    static let glassViewViewerPoseEnabled = true

    /// IMU prediction between ARKit frames.
    static let glassViewIMUPredictionEnabled = true

    /// ARKit plane detection for scene depth hints.
    static let glassViewPlaneDetectionEnabled = true

    /// Stage A2 parallax depth tuning — enabled with sensor fusion.
    static let planeDepthSelfTuningEnabled = true

    /// Exponential smoothing for fused scene depth (0 = frozen, 1 = raw).
    static let sceneDepthFilterAlpha: Float = 0.12

    static let fusionProcessingRateHz: Double = 30

    /// Force direct camera UV mapping — off now that Metal feed is stable.
    static let glassViewForcePassthroughPreview = false

    /// LiDAR scene-depth maps — off on iPhone 12 mini baseline.
    static let glassViewSceneDepthSemanticsEnabled = false

    static let viewerPoseUpdateRateHz: Double = 12

    /// Amplifies head-relative lateral offset for visible parallax at screen edges.
    static let viewerPoseLateralGain: Float = 1.0

    static let glassViewFullReprojectionThreshold: Float = 0.45
    static let glassViewSimplifiedReprojectionThreshold: Float = 0.25

    static let glassViewDebugMetricsEnabled = false

    /// Multiplies planar parallax — 1.0 ≈ physically correct at scene depth.
    static let glassViewWarpExaggerationGain: Float = 1.0

    /// Scales lateral phone-motion parallax in WARP mode.
    static let glassViewMotionParallaxStrength: Float = 1.8

    /// Scales head-motion parallax from TrueDepth / face landmarks.
    static let glassViewHeadParallaxStrength: Float = 1.4

    /// Soft ceiling on parallax UV shift — prevents edge streaking past ~20 cm motion.
    static let glassViewMaxParallaxUVOffset: Float = 0.12

    /// Temporal low-pass on parallax + window scale — reduces VIO / face jitter.
    static let glassViewParallaxSmoothingEnabled = true

    /// EMA alpha when motion is below the jitter threshold (hold still).
    static let glassViewParallaxSmoothingAlphaStill: Float = 0.10

    /// EMA alpha when the user is deliberately moving head or phone.
    static let glassViewParallaxSmoothingAlphaMoving: Float = 0.38

    /// UV delta below this is treated as sensor noise and filtered heavily.
    static let glassViewParallaxJitterThresholdUV: Float = 0.0018

    /// EMA alpha for window magnification (separate from parallax).
    static let glassViewWindowScaleSmoothingAlpha: Float = 0.12

    /// EMA on TrueDepth lateral offset before parallax (0 = frozen, 1 = raw).
    static let viewerPoseSmoothingAlpha: Float = 0.22

    /// Debug seam — off now that Metal feed and warp path are verified.
    static let glassViewDebugForcedSplitOffset = false

    /// Stable 2D parallax warp for a flat scene — avoids broken 3D mesh folding.
    static let glassViewUsePlanarMotionWarp = true

    /// Zoom passthrough so screen FOV matches a physical window at eye distance.
    static let glassViewWindowScaleEnabled = true

    /// Blend toward optically correct window scale (0 = camera FOV, 1 = full correction).
    static let glassViewWindowScaleStrength: Float = 0.55

    /// Cap — full physical correction can require 5×+ crop on wide rear camera.
    static let glassViewWindowScaleMaximum: Float = 2.8

    /// Correct for rear camera ≠ eye line-of-sight through the display center.
    static let glassViewStaticEyeAlignmentEnabled = true

    /// Scale on the static eye-camera baseline offset (fine tune after recenter).
    static let glassViewStaticAlignmentStrength: Float = 1.0

    /// Blend parallax depth toward `scenePlaneDepthMeters` (1 = always use configured).
    static let glassViewAlignmentDepthBias: Float = 0.72

    /// Manual UV trim after optical alignment — tune per scene if edges still slip.
    static let glassViewAlignmentTrimUV = SIMD2<Float>(0, 0)

    #if os(iOS)
    static var deviceOpticalProfile: DeviceOpticalProfile {
        DeviceOpticalProfile.current
    }
    #endif

    // MARK: - Legacy perceptual tuning (camera preview fallback)

    /// Physical camera zoom that reads as neutral 1.0× — used only when `useTransparentWindow` is false.
    static let perceptualBaselineZoom: CGFloat = 1.18
    static let previewVideoGravity: AVLayerVideoGravity = .resizeAspectFill
    static let cameraEyeHorizontalOffset: CGFloat = 0
    static let cameraEyeVerticalOffset: CGFloat = 14
    static let perceptualWindowStabilizationEnabled = false
    static let gazeParallaxStrength: CGFloat = 200
    static let perceptualPreviewOverscan: CGFloat = 1.08

    /// Local subject magnification during lens state, relative to the window baseline.
    static let lensMagnification: CGFloat = 1.25

    /// Radius of the local lens region in points.
    static let lensRegionRadius: CGFloat = 88

    static let lensAnimationDuration: TimeInterval = 0.45
}
