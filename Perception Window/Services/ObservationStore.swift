//
//  ObservationStore.swift
//  Perception Window
//

import Foundation

actor ObservationStore {
    private let directoryURL: URL

    init() {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        directoryURL = appSupport.appendingPathComponent("Observations", isDirectory: true)
        try? FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
    }

    @discardableResult
    func save(
        frameJPEG: Data,
        result: AnalysisResult,
        userQuestion: String? = nil
    ) async throws -> ObservationRecord {
        let id = UUID()
        let folder = directoryURL.appendingPathComponent(id.uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)

        let frameFilename = "frame.jpg"
        let frameURL = folder.appendingPathComponent(frameFilename)
        try frameJPEG.write(to: frameURL)

        let observationPrimary: String?
        let observationDetail: String?
        let focusX: Double?
        let focusY: Double?
        let subject: String?

        switch result.outcome {
        case .observation(let observation):
            observationPrimary = observation.primary
            observationDetail = observation.detail
            focusX = Double(observation.anchor.x)
            focusY = Double(observation.anchor.y)
            subject = observation.subject
        case .nothingVisible:
            observationPrimary = nil
            observationDetail = nil
            focusX = nil
            focusY = nil
            subject = nil
        }

        let record = ObservationRecord(
            id: id,
            timestamp: Date(),
            modelResponse: result.rawResponse,
            observationPrimary: observationPrimary,
            observationDetail: observationDetail,
            userQuestion: userQuestion,
            recognizedSubject: subject,
            focusX: focusX,
            focusY: focusY,
            frameFilename: frameFilename
        )

        let metadataURL = folder.appendingPathComponent("record.json")
        let data = try JSONEncoder().encode(record)
        try data.write(to: metadataURL)

        return record
    }
}
