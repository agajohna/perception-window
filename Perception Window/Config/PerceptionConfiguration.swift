//
//  PerceptionConfiguration.swift
//  Perception Window
//

import AVFoundation
import Foundation

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

    // MARK: - Perceptual window

    /// Physical camera zoom that reads as neutral 1.0× — tune on your device with the printer edge test.
    /// Candidates: 1.00, 1.10, 1.18, 1.25, 1.30
    static let perceptualBaselineZoom: CGFloat = 1.18

    /// `resizeAspectFill` fills the screen (glass window). Tune zoom if edge alignment is off.
    /// Use `.resizeAspect` only if you prefer geometric letterboxing over full-bleed.
    static let previewVideoGravity: AVLayerVideoGravity = .resizeAspectFill

    /// Local subject magnification during lens state, relative to the window baseline.
    static let lensMagnification: CGFloat = 1.25

    /// Radius of the local lens region in points.
    static let lensRegionRadius: CGFloat = 88

    static let lensAnimationDuration: TimeInterval = 0.45
}
