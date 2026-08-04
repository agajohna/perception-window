//
//  EntityRegistry.swift
//  Perception Window
//

import Foundation

/// Links conservative retrieval hints to persistent entities over time.
actor EntityRegistry {
    private let directoryURL: URL
    private var entities: [UUID: PersistentEntity] = [:]
    private var hintIndex: [String: UUID] = [:]

    init() {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        directoryURL = appSupport.appendingPathComponent("Entities", isDirectory: true)
        try? FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        loadEntities()
    }

    func resolve(
        temporarySubjectKey: String,
        matchConfidence: Float
    ) -> PersistentEntity {
        // Conservative — only link hints when confidence is reasonable.
        if matchConfidence >= PerceptionConfiguration.subjectMatchThreshold,
           let existingID = hintIndex[temporarySubjectKey],
           var entity = entities[existingID] {
            if !entity.retrievalHints.contains(temporarySubjectKey) {
                entity.retrievalHints.append(temporarySubjectKey)
            }
            entity.lastSeen = Date()
            entities[existingID] = entity
            persist(entity)
            return entity
        }

        let entity = PersistentEntity(
            retrievalHints: [temporarySubjectKey],
            visitCount: 0
        )
        entities[entity.id] = entity
        hintIndex[temporarySubjectKey] = entity.id
        persist(entity)
        return entity
    }

    func recordVisit(for entityID: UUID) {
        guard var entity = entities[entityID] else { return }
        entity.visitCount += 1
        entity.lastSeen = Date()
        entities[entityID] = entity
        persist(entity)
    }

    func entity(for id: UUID) -> PersistentEntity? {
        entities[id]
    }

    private func loadEntities() {
        guard
            let files = try? FileManager.default.contentsOfDirectory(
                at: directoryURL,
                includingPropertiesForKeys: nil
            )
        else {
            return
        }

        for file in files where file.pathExtension == "json" {
            guard
                let data = try? Data(contentsOf: file),
                let entity = try? JSONDecoder().decode(PersistentEntity.self, from: data)
            else {
                continue
            }
            entities[entity.id] = entity
            for hint in entity.retrievalHints {
                hintIndex[hint] = entity.id
            }
        }
    }

    private func persist(_ entity: PersistentEntity) {
        let url = directoryURL.appendingPathComponent("\(entity.id.uuidString).json")
        guard let data = try? JSONEncoder().encode(entity) else { return }
        try? data.write(to: url)
    }
}
