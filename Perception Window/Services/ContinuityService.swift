//
//  ContinuityService.swift
//  Perception Window
//

import CoreGraphics
import Foundation

/// Stage 3 — what has changed since last time?
struct ContinuityService {
    private let analysisService = AnalysisService()

    func perceive(
        preparedFrame: PreparedFrame,
        identity: SubjectIdentity,
        comparison: ComparisonSelection?,
        comparisonJPEG: Data?,
        hasBaseline: Bool,
        isSameSession: Bool,
        useDemoFirstVisit: Bool
    ) async -> AnalysisResult {
        if isSameSession {
            return .silent(.sameSessionContinuation, rawResponse: "session:continuation")
        }

        if identity.matchConfidence < PerceptionConfiguration.subjectMatchThreshold {
            return .silent(
                .subjectMatchUncertain,
                rawResponse: "match:uncertain",
                subjectMatchConfidence: Double(identity.matchConfidence)
            )
        }

        if !hasBaseline {
            return await firstVisit(
                preparedFrame: preparedFrame,
                identity: identity,
                useDemoFirstVisit: useDemoFirstVisit
            )
        }

        guard let comparison, let comparisonJPEG else {
            return .silent(.comparisonUnavailable, rawResponse: "continuity:no-target")
        }

        return await compare(
            preparedFrame: preparedFrame,
            comparisonJPEG: comparisonJPEG,
            comparison: comparison,
            identity: identity
        )
    }

    private func firstVisit(
        preparedFrame: PreparedFrame,
        identity: SubjectIdentity,
        useDemoFirstVisit: Bool
    ) async -> AnalysisResult {
        if useDemoFirstVisit, let primary = identity.firstVisitPrimary {
            let observation = PerceptionObservation(
                primary: primary,
                detail: identity.firstVisitDetail,
                entityID: identity.persistentEntityID,
                temporarySubjectKey: identity.temporarySubjectKey,
                domain: identity.domain,
                anchor: identity.anchor
            )
            return AnalysisResult(
                outcome: .observation(observation),
                rawResponse: "first:\(identity.temporarySubjectKey)",
                subjectMatchConfidence: Double(identity.matchConfidence),
                isBaseline: true
            )
        }

        do {
            let result = try await analysisService.observe(
                jpeg: preparedFrame.analysisJPEG,
                identity: identity
            )
            return AnalysisResult(
                outcome: result.outcome,
                rawResponse: result.rawResponse,
                evidence: result.evidence,
                subjectMatchConfidence: result.subjectMatchConfidence ?? Double(identity.matchConfidence),
                comparisonTargetID: result.comparisonTargetID,
                isBaseline: true
            )
        } catch {
            return Self.failureResult(for: error)
        }
    }

    private func compare(
        preparedFrame: PreparedFrame,
        comparisonJPEG: Data,
        comparison: ComparisonSelection,
        identity: SubjectIdentity
    ) async -> AnalysisResult {
        if APIConfiguration.openAIAPIKey != nil {
            do {
                return try await analysisService.compareContinuity(
                    currentJPEG: preparedFrame.analysisJPEG,
                    priorJPEG: comparisonJPEG,
                    priorRecord: comparison.record,
                    identity: identity
                )
            } catch {
                return Self.failureResult(for: error)
            }
        }

        return .silent(.comparisonUnavailable, rawResponse: "continuity:needs-api")
    }

    private static func failureResult(for error: Error) -> AnalysisResult {
        if error is URLError {
            return .silent(.networkFailure, rawResponse: "network:\(error.localizedDescription)")
        }
        return .silent(.modelFailure, rawResponse: "model:\(error.localizedDescription)")
    }
}
