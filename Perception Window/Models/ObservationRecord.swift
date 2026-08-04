//
//  ObservationRecord.swift
//  Perception Window
//

import Foundation

struct ObservationRecord: Codable, Identifiable {
    let id: UUID
    let timestamp: Date
    let modelResponse: String
    let observationPrimary: String?
    let observationDetail: String?
    let userQuestion: String?
    let recognizedSubject: String?
    let focusX: Double?
    let focusY: Double?
    let frameFilename: String

    init(
        id: UUID = UUID(),
        timestamp: Date = Date(),
        modelResponse: String,
        observationPrimary: String?,
        observationDetail: String? = nil,
        userQuestion: String? = nil,
        recognizedSubject: String? = nil,
        focusX: Double? = nil,
        focusY: Double? = nil,
        frameFilename: String
    ) {
        self.id = id
        self.timestamp = timestamp
        self.modelResponse = modelResponse
        self.observationPrimary = observationPrimary
        self.observationDetail = observationDetail
        self.userQuestion = userQuestion
        self.recognizedSubject = recognizedSubject
        self.focusX = focusX
        self.focusY = focusY
        self.frameFilename = frameFilename
    }
}
