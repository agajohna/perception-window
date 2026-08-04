//
//  ComparisonStrategy.swift
//  Perception Window
//

import Foundation

/// How a prior observation was chosen for continuity comparison.
enum ComparisonStrategy: String, Codable, Equatable {
    case mostRecent
    case baseline
    case bestHistorical
    case sameSeason
}
