//
//  Observation.swift
//  Perception Window
//

import CoreGraphics
import Foundation

struct PerceptionObservation: Equatable, Identifiable {
    var id: String { primary }

    let primary: String
    let detail: String?
    let entityID: UUID?
    /// Retrieval hint only — never shown in UI.
    let temporarySubjectKey: String?
    let domain: CuriosityDomain?
    let anchor: CGPoint

    init(
        primary: String,
        detail: String? = nil,
        entityID: UUID? = nil,
        temporarySubjectKey: String? = nil,
        domain: CuriosityDomain? = nil,
        anchor: CGPoint
    ) {
        self.primary = primary
        self.detail = detail
        self.entityID = entityID
        self.temporarySubjectKey = temporarySubjectKey
        self.domain = domain
        self.anchor = anchor
    }

    /// Legacy accessor — prefer entityID.
    var subject: String? { temporarySubjectKey }
}

struct AnalysisResult: Equatable {
    enum Outcome: Equatable {
        case observation(PerceptionObservation)
        case silent(SilenceReason)
    }

    let outcome: Outcome
    let rawResponse: String
    let evidence: [String]
    let subjectMatchConfidence: Double?
    let comparisonTargetID: UUID?
    let isBaseline: Bool

    init(
        outcome: Outcome,
        rawResponse: String,
        evidence: [String] = [],
        subjectMatchConfidence: Double? = nil,
        comparisonTargetID: UUID? = nil,
        isBaseline: Bool = false
    ) {
        self.outcome = outcome
        self.rawResponse = rawResponse
        self.evidence = evidence
        self.subjectMatchConfidence = subjectMatchConfidence
        self.comparisonTargetID = comparisonTargetID
        self.isBaseline = isBaseline
    }

    static func silent(
        _ reason: SilenceReason,
        rawResponse: String = "",
        evidence: [String] = [],
        subjectMatchConfidence: Double? = nil,
        comparisonTargetID: UUID? = nil
    ) -> AnalysisResult {
        AnalysisResult(
            outcome: .silent(reason),
            rawResponse: rawResponse,
            evidence: evidence,
            subjectMatchConfidence: subjectMatchConfidence,
            comparisonTargetID: comparisonTargetID
        )
    }
}
