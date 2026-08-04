//
//  PerceptionConfiguration.swift
//  Perception Window
//

import Foundation

enum PerceptionConfiguration {
    static let useDemoPerception = true

    /// Learned curiosity weights — internal, not user-facing modes.
    static var curiosityProfile: CuriosityProfile = .default

    /// Time for the eye ring to fill — perception coming into focus.
    static let focusFillDuration: TimeInterval = 1.0

    /// Pause between observations when attention moves.
    static let attentionTransitionPause: TimeInterval = 0.5

    static let observationFadeDuration: TimeInterval = 0.35
    static let resampleInterval: TimeInterval = 1.5

    /// Same entity within this window continues the current inspection — no continuity comparison.
    static let continuityRevisitInterval: TimeInterval = 120

    /// Minimum confidence to link a retrieval hint to an existing entity.
    static let subjectMatchThreshold: Float = 0.15
}
