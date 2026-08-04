//
//  ObservationRecord.swift
//  Perception Window
//

import Foundation

struct ObservationRecord: Codable, Identifiable {
    let id: UUID
    let entityID: UUID
    let timestamp: Date

    // Evidence
    let frameFilename: String
    let cameraMetadata: CameraCaptureMetadata?
    let placeContext: PlaceContext?

    // Interpretation — separate from evidence
    let userFacingSentence: String?
    let userFacingDetail: String?
    let rawVisualFindings: [String]

    // Retrieval hints — not identity
    let temporarySubjectKey: String?
    let subjectMatchConfidence: Double?

    // Model provenance
    let modelID: String?
    let modelVersion: String?
    let rawModelResponse: String

    // Continuity context
    let comparisonTargetID: UUID?
    let comparisonStrategy: ComparisonStrategy?
    let isBaseline: Bool

    // Internal silence — UI shows nothing when set
    let silenceReason: SilenceReason?

    let focusX: Double?
    let focusY: Double?

    init(
        id: UUID = UUID(),
        entityID: UUID,
        timestamp: Date = Date(),
        frameFilename: String,
        cameraMetadata: CameraCaptureMetadata? = nil,
        placeContext: PlaceContext? = nil,
        userFacingSentence: String? = nil,
        userFacingDetail: String? = nil,
        rawVisualFindings: [String] = [],
        temporarySubjectKey: String? = nil,
        subjectMatchConfidence: Double? = nil,
        modelID: String? = nil,
        modelVersion: String? = nil,
        rawModelResponse: String = "",
        comparisonTargetID: UUID? = nil,
        comparisonStrategy: ComparisonStrategy? = nil,
        isBaseline: Bool = false,
        silenceReason: SilenceReason? = nil,
        focusX: Double? = nil,
        focusY: Double? = nil
    ) {
        self.id = id
        self.entityID = entityID
        self.timestamp = timestamp
        self.frameFilename = frameFilename
        self.cameraMetadata = cameraMetadata
        self.placeContext = placeContext
        self.userFacingSentence = userFacingSentence
        self.userFacingDetail = userFacingDetail
        self.rawVisualFindings = rawVisualFindings
        self.temporarySubjectKey = temporarySubjectKey
        self.subjectMatchConfidence = subjectMatchConfidence
        self.modelID = modelID
        self.modelVersion = modelVersion
        self.rawModelResponse = rawModelResponse
        self.comparisonTargetID = comparisonTargetID
        self.comparisonStrategy = comparisonStrategy
        self.isBaseline = isBaseline
        self.silenceReason = silenceReason
        self.focusX = focusX
        self.focusY = focusY
    }

    // MARK: - Legacy field access

    var observationPrimary: String? { userFacingSentence }
    var observationDetail: String? { userFacingDetail }
    var recognizedSubject: String? { temporarySubjectKey }
    var modelResponse: String { rawModelResponse }

    enum CodingKeys: String, CodingKey {
        case id, entityID, timestamp, frameFilename
        case cameraMetadata, placeContext
        case userFacingSentence, userFacingDetail, rawVisualFindings
        case temporarySubjectKey, subjectMatchConfidence
        case modelID, modelVersion, rawModelResponse
        case comparisonTargetID, comparisonStrategy, isBaseline, silenceReason
        case focusX, focusY
        // Legacy keys for records saved before this schema
        case observationPrimary, observationDetail, recognizedSubject, modelResponse
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        timestamp = try container.decode(Date.self, forKey: .timestamp)
        frameFilename = try container.decode(String.self, forKey: .frameFilename)
        focusX = try container.decodeIfPresent(Double.self, forKey: .focusX)
        focusY = try container.decodeIfPresent(Double.self, forKey: .focusY)

        cameraMetadata = try container.decodeIfPresent(CameraCaptureMetadata.self, forKey: .cameraMetadata)
        placeContext = try container.decodeIfPresent(PlaceContext.self, forKey: .placeContext)
        rawVisualFindings = try container.decodeIfPresent([String].self, forKey: .rawVisualFindings) ?? []
        subjectMatchConfidence = try container.decodeIfPresent(Double.self, forKey: .subjectMatchConfidence)
        modelID = try container.decodeIfPresent(String.self, forKey: .modelID)
        modelVersion = try container.decodeIfPresent(String.self, forKey: .modelVersion)
        comparisonTargetID = try container.decodeIfPresent(UUID.self, forKey: .comparisonTargetID)
        comparisonStrategy = try container.decodeIfPresent(ComparisonStrategy.self, forKey: .comparisonStrategy)
        isBaseline = try container.decodeIfPresent(Bool.self, forKey: .isBaseline) ?? false
        silenceReason = try container.decodeIfPresent(SilenceReason.self, forKey: .silenceReason)

        let legacySubject = try container.decodeIfPresent(String.self, forKey: .recognizedSubject)
        temporarySubjectKey = try container.decodeIfPresent(String.self, forKey: .temporarySubjectKey) ?? legacySubject

        let legacyPrimary = try container.decodeIfPresent(String.self, forKey: .observationPrimary)
        userFacingSentence = try container.decodeIfPresent(String.self, forKey: .userFacingSentence) ?? legacyPrimary

        let legacyDetail = try container.decodeIfPresent(String.self, forKey: .observationDetail)
        userFacingDetail = try container.decodeIfPresent(String.self, forKey: .userFacingDetail) ?? legacyDetail

        let legacyResponse = try container.decodeIfPresent(String.self, forKey: .modelResponse)
        rawModelResponse = try container.decodeIfPresent(String.self, forKey: .rawModelResponse) ?? legacyResponse ?? ""

        if let entityID = try container.decodeIfPresent(UUID.self, forKey: .entityID) {
            self.entityID = entityID
        } else {
            self.entityID = UUID()
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(entityID, forKey: .entityID)
        try container.encode(timestamp, forKey: .timestamp)
        try container.encode(frameFilename, forKey: .frameFilename)
        try container.encodeIfPresent(cameraMetadata, forKey: .cameraMetadata)
        try container.encodeIfPresent(placeContext, forKey: .placeContext)
        try container.encodeIfPresent(userFacingSentence, forKey: .userFacingSentence)
        try container.encodeIfPresent(userFacingDetail, forKey: .userFacingDetail)
        try container.encode(rawVisualFindings, forKey: .rawVisualFindings)
        try container.encodeIfPresent(temporarySubjectKey, forKey: .temporarySubjectKey)
        try container.encodeIfPresent(subjectMatchConfidence, forKey: .subjectMatchConfidence)
        try container.encodeIfPresent(modelID, forKey: .modelID)
        try container.encodeIfPresent(modelVersion, forKey: .modelVersion)
        try container.encode(rawModelResponse, forKey: .rawModelResponse)
        try container.encodeIfPresent(comparisonTargetID, forKey: .comparisonTargetID)
        try container.encodeIfPresent(comparisonStrategy, forKey: .comparisonStrategy)
        try container.encode(isBaseline, forKey: .isBaseline)
        try container.encodeIfPresent(silenceReason, forKey: .silenceReason)
        try container.encodeIfPresent(focusX, forKey: .focusX)
        try container.encodeIfPresent(focusY, forKey: .focusY)
    }
}
