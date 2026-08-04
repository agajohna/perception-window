//
//  CuriosityProfile.swift
//  Perception Window
//

import Foundation

/// Domains of curiosity — internal only, never shown as modes or packs.
enum CuriosityDomain: String, Codable, CaseIterable, Equatable {
    case plants
    case electronics
    case art
    case objects
    case general
}

/// What the user naturally investigates, learned over time.
/// Used to rank which single observation to surface — not to switch "modes."
struct CuriosityProfile: Equatable {
    var weights: [CuriosityDomain: Double]

    static let `default` = CuriosityProfile(weights: [
        .plants: 1.0,
        .electronics: 1.0,
        .art: 1.0,
        .objects: 1.0,
        .general: 1.0
    ])

    func weight(for domain: CuriosityDomain) -> Double {
        weights[domain] ?? 1.0
    }

    /// Reinforce a domain after the user investigates it. Subtle — not a mode switch.
    mutating func reinforce(_ domain: CuriosityDomain, by amount: Double = 0.05) {
        let current = weights[domain] ?? 1.0
        weights[domain] = min(current + amount, 2.0)
    }
}
