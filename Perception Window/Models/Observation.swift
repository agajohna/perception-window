//
//  Observation.swift
//  Perception Window
//

import CoreGraphics

struct PerceptionObservation: Equatable, Identifiable {
    var id: String { primary }

    /// One observation — why this is worth noticing.
    let primary: String
    /// Optional depth — shown only when the user asks.
    let detail: String?
    let subject: String?
    /// Internal domain for curiosity learning — never shown in UI.
    let domain: CuriosityDomain?
    /// Normalized anchor on the subject, origin top-left (0...1).
    let anchor: CGPoint

    init(
        primary: String,
        detail: String? = nil,
        subject: String? = nil,
        domain: CuriosityDomain? = nil,
        anchor: CGPoint
    ) {
        self.primary = primary
        self.detail = detail
        self.subject = subject
        self.domain = domain
        self.anchor = anchor
    }
}

struct AnalysisResult: Equatable {
    enum Outcome: Equatable {
        case observation(PerceptionObservation)
        case nothingVisible
    }

    let outcome: Outcome
    let rawResponse: String
}
