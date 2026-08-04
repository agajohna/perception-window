//
//  SilenceReason.swift
//  Perception Window
//

import Foundation

/// Internal pipeline state — all appear as silence in the UI for now.
enum SilenceReason: String, Codable, Equatable {
    case noMeaningfulChange
    case insufficientImageQuality
    case subjectMatchUncertain
    case comparisonUnavailable
    case modelFailure
    case sameSessionContinuation
    case noSubjectIdentified
}
