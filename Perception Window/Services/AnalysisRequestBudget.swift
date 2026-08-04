//
//  AnalysisRequestBudget.swift
//  Perception Window
//

import Foundation

/// Prototype guardrails — generous limits, strict shape. No invisible retry loops.
actor AnalysisRequestBudget {
    private var holdAnalysisConsumed = false
    private var dailyCount = 0
    private var dailyResetDay: Date = Calendar.current.startOfDay(for: Date())
    private var lastRequestByEntity: [UUID: Date] = [:]
    private(set) var logs: [AnalysisRequestLog] = []

    func beginHold() {
        holdAnalysisConsumed = false
    }

    func canRequest(entityID: UUID?) -> (allowed: Bool, reason: SilenceReason?) {
        resetDailyCountIfNeeded()

        if holdAnalysisConsumed {
            return (false, .sameSessionContinuation)
        }

        if dailyCount >= PerceptionConfiguration.dailyRequestCeiling {
            return (false, .rateLimited)
        }

        if let entityID, let last = lastRequestByEntity[entityID] {
            let elapsed = Date().timeIntervalSince(last)
            if elapsed < PerceptionConfiguration.requestCooldownInterval {
                return (false, .sameSessionContinuation)
            }
        }

        return (true, nil)
    }

    func recordRequest(
        stage: AnalysisStage,
        entityID: UUID?,
        analysisImageBytes: Int
    ) {
        resetDailyCountIfNeeded()
        holdAnalysisConsumed = true
        dailyCount += 1

        if let entityID {
            lastRequestByEntity[entityID] = Date()
        }

        let estimatedCost = Self.estimatedCostUSD(imageBytes: analysisImageBytes, stage: stage)
        let log = AnalysisRequestLog(
            timestamp: Date(),
            stage: stage,
            entityID: entityID,
            estimatedCostUSD: estimatedCost,
            modelID: APIConfiguration.model,
            analysisImageBytes: analysisImageBytes
        )
        logs.append(log)

        #if DEBUG
        print("[Curiosity] API \(stage.rawValue) ~$\(String(format: "%.4f", estimatedCost)) (\(analysisImageBytes) bytes)")
        #endif
    }

    private func resetDailyCountIfNeeded() {
        let today = Calendar.current.startOfDay(for: Date())
        if today > dailyResetDay {
            dailyCount = 0
            dailyResetDay = today
        }
    }

    /// Rough prototype estimate — refine with backend metering later.
    private static func estimatedCostUSD(imageBytes: Int, stage: AnalysisStage) -> Double {
        let imageCost = Double(imageBytes) / 1_000_000 * 0.005
        let tokenCost = stage == .continuityComparison ? 0.003 : 0.002
        return imageCost + tokenCost
    }
}
