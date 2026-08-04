//
//  PerceptionConfiguration.swift
//  Perception Window
//

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

    static let minimumSharpness: Float = 18
    static let minimumBrightness: Float = 0.12
    static let maximumBrightness: Float = 0.92
}
