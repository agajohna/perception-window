//
//  ObservationStore.swift
//  Perception Window
//

import Foundation

struct ComparisonSelection {
    let record: ObservationRecord
    let strategy: ComparisonStrategy
}

actor ObservationStore {
    private let directoryURL: URL

    init() {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        directoryURL = appSupport.appendingPathComponent("Observations", isDirectory: true)
        try? FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
    }

    // MARK: - Retrieval (structured for future strategies)

    func records(forEntity entityID: UUID) -> [ObservationRecord] {
        allRecords()
            .filter { $0.entityID == entityID }
            .sorted { $0.timestamp < $1.timestamp }
    }

    func baselineRecord(forEntity entityID: UUID) -> ObservationRecord? {
        records(forEntity: entityID).first { $0.isBaseline }
            ?? records(forEntity: entityID).first
    }

    func mostRecentRecord(
        forEntity entityID: UUID,
        excludingWithin interval: TimeInterval = 0
    ) -> ObservationRecord? {
        let cutoff = Date().addingTimeInterval(-interval)
        return records(forEntity: entityID)
            .filter { $0.timestamp < cutoff && ($0.userFacingSentence != nil || $0.isBaseline) }
            .max(by: { $0.timestamp < $1.timestamp })
    }

    /// Best historical comparison — largest temporal gap useful for slow change.
    func bestHistoricalRecord(
        forEntity entityID: UUID,
        excludingWithin interval: TimeInterval
    ) -> ObservationRecord? {
        let cutoff = Date().addingTimeInterval(-interval)
        let candidates = records(forEntity: entityID).filter { $0.timestamp < cutoff }
        guard candidates.count >= 2 else { return candidates.first }

        // Prefer the oldest baseline-adjacent record when recent pairs look identical.
        if let baseline = baselineRecord(forEntity: entityID), baseline.timestamp < cutoff {
            return baseline
        }
        return candidates.min(by: { $0.timestamp < $1.timestamp })
    }

    /// Demo path: most recent outside the session window, structured for richer strategies later.
    func comparisonTarget(
        forEntity entityID: UUID,
        revisitInterval: TimeInterval
    ) -> ComparisonSelection? {
        let entityRecords = records(forEntity: entityID)
        guard !entityRecords.isEmpty else { return nil }

        let cutoff = Date().addingTimeInterval(-revisitInterval)
        let outsideSession = entityRecords.filter { $0.timestamp < cutoff }

        if let recent = outsideSession.max(by: { $0.timestamp < $1.timestamp }) {
            return ComparisonSelection(record: recent, strategy: .mostRecent)
        }

        if let baseline = baselineRecord(forEntity: entityID) {
            return ComparisonSelection(record: baseline, strategy: .baseline)
        }

        return nil
    }

    func frameJPEG(for record: ObservationRecord) -> Data? {
        let url = folderURL(for: record).appendingPathComponent(record.frameFilename)
        return try? Data(contentsOf: url)
    }

    /// Cropped/resized frame used for API comparison — falls back to source frame.
    func analysisJPEG(for record: ObservationRecord) -> Data? {
        if let analysisFrameFilename = record.analysisFrameFilename {
            let url = folderURL(for: record).appendingPathComponent(analysisFrameFilename)
            if let data = try? Data(contentsOf: url) {
                return data
            }
        }
        return frameJPEG(for: record)
    }

    func hasBaseline(forEntity entityID: UUID) -> Bool {
        records(forEntity: entityID).contains { $0.isBaseline }
    }

    // MARK: - Persistence

    @discardableResult
    func save(
        preparedFrame: PreparedFrame,
        entityID: UUID,
        identity: SubjectIdentity?,
        result: AnalysisResult,
        cameraMetadata: CameraCaptureMetadata? = nil,
        placeContext: PlaceContext? = nil,
        comparisonStrategy: ComparisonStrategy? = nil
    ) async throws -> ObservationRecord {
        let id = UUID()
        let folder = directoryURL.appendingPathComponent(id.uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)

        let frameFilename = "frame.jpg"
        let analysisFrameFilename = "analysis.jpg"
        try preparedFrame.sourceJPEG.write(to: folder.appendingPathComponent(frameFilename))
        try preparedFrame.analysisJPEG.write(to: folder.appendingPathComponent(analysisFrameFilename))

        let userFacingSentence: String?
        let userFacingDetail: String?
        let silenceReason: SilenceReason?
        let focusX: Double?
        let focusY: Double?

        switch result.outcome {
        case .observation(let observation):
            userFacingSentence = observation.primary
            userFacingDetail = observation.detail
            silenceReason = nil
            focusX = Double(observation.anchor.x)
            focusY = Double(observation.anchor.y)
        case .silent(let reason):
            userFacingSentence = nil
            userFacingDetail = nil
            silenceReason = reason
            focusX = identity.map { Double($0.anchor.x) }
            focusY = identity.map { Double($0.anchor.y) }
        }

        let record = ObservationRecord(
            id: id,
            entityID: entityID,
            frameFilename: frameFilename,
            analysisFrameFilename: analysisFrameFilename,
            cameraMetadata: cameraMetadata,
            placeContext: placeContext,
            userFacingSentence: userFacingSentence,
            userFacingDetail: userFacingDetail,
            rawVisualFindings: result.evidence,
            temporarySubjectKey: identity?.temporarySubjectKey,
            subjectMatchConfidence: result.subjectMatchConfidence ?? identity.map { Double($0.matchConfidence) },
            modelID: APIConfiguration.model,
            modelVersion: APIConfiguration.modelVersion,
            rawModelResponse: result.rawResponse,
            comparisonTargetID: result.comparisonTargetID,
            comparisonStrategy: comparisonStrategy,
            isBaseline: result.isBaseline,
            silenceReason: silenceReason,
            focusX: focusX,
            focusY: focusY
        )

        let metadataURL = folder.appendingPathComponent("record.json")
        try JSONEncoder().encode(record).write(to: metadataURL)
        return record
    }

    private func allRecords() -> [ObservationRecord] {
        guard
            let folders = try? FileManager.default.contentsOfDirectory(
                at: directoryURL,
                includingPropertiesForKeys: nil
            )
        else {
            return []
        }

        return folders.compactMap { folder in
            let metadataURL = folder.appendingPathComponent("record.json")
            guard
                let data = try? Data(contentsOf: metadataURL),
                let record = try? JSONDecoder().decode(ObservationRecord.self, from: data)
            else {
                return nil
            }
            return record
        }
    }

    private func folderURL(for record: ObservationRecord) -> URL {
        directoryURL.appendingPathComponent(record.id.uuidString, isDirectory: true)
    }
}
