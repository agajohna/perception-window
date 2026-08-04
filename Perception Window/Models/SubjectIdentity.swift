//
//  SubjectIdentity.swift
//  Perception Window
//

import CoreGraphics
import Foundation

/// Conservative attention pass output — hint only, not yet linked to a persistent entity.
struct SubjectResolution: Equatable {
    let temporarySubjectKey: String
    let domain: CuriosityDomain?
    let anchor: CGPoint
    let matchConfidence: Float
    let firstVisitPrimary: String?
    let firstVisitDetail: String?
}

/// Resolved attention target — temporary hints linked to a persistent entity.
struct SubjectIdentity: Equatable {
    let temporarySubjectKey: String
    let persistentEntityID: UUID
    let relationshipName: String?
    let domain: CuriosityDomain?
    let anchor: CGPoint
    let matchConfidence: Float
    let firstVisitPrimary: String?
    let firstVisitDetail: String?

    init(resolution: SubjectResolution, entity: PersistentEntity) {
        temporarySubjectKey = resolution.temporarySubjectKey
        persistentEntityID = entity.id
        relationshipName = entity.relationshipName
        domain = resolution.domain
        anchor = resolution.anchor
        matchConfidence = resolution.matchConfidence
        firstVisitPrimary = resolution.firstVisitPrimary
        firstVisitDetail = resolution.firstVisitDetail
    }
}
