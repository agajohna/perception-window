//
//  PersistentEntity.swift
//  Perception Window
//

import Foundation

/// A subject that persists across visits — identity emerges from repetition, not classification.
struct PersistentEntity: Codable, Identifiable, Equatable {
    let id: UUID
    var relationshipName: String?
    /// Retrieval hints only — never treated as permanent identity.
    var retrievalHints: [String]
    let firstSeen: Date
    var lastSeen: Date
    var visitCount: Int

    init(
        id: UUID = UUID(),
        relationshipName: String? = nil,
        retrievalHints: [String] = [],
        firstSeen: Date = Date(),
        lastSeen: Date = Date(),
        visitCount: Int = 0
    ) {
        self.id = id
        self.relationshipName = relationshipName
        self.retrievalHints = retrievalHints
        self.firstSeen = firstSeen
        self.lastSeen = lastSeen
        self.visitCount = visitCount
    }
}
