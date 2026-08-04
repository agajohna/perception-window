//
//  AnalysisStage.swift
//  Perception Window
//

import Foundation

/// Which pipeline stage triggered an API call — for cost accounting.
enum AnalysisStage: String, Codable {
    case firstObservation
    case continuityComparison
}

struct AnalysisRequestLog: Codable, Equatable {
    let timestamp: Date
    let stage: AnalysisStage
    let entityID: UUID?
    let estimatedCostUSD: Double
    let modelID: String
    let analysisImageBytes: Int
}
