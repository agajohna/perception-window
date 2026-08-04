//
//  SubjectIdentifier.swift
//  Perception Window
//

import CoreGraphics
import Foundation
import Vision

#if os(iOS)
import UIKit
#endif

/// Lightweight attention pass — produces conservative retrieval hints, not identity.
struct SubjectIdentifier {
    private struct CatalogEntry {
        let temporarySubjectKey: String
        let domain: CuriosityDomain
        let firstVisitPrimary: String
        let firstVisitDetail: String?
        let classificationKeywords: [String]
        let textKeywords: [String]
    }

    private static let catalog: [CatalogEntry] = [
        CatalogEntry(
            temporarySubjectKey: "object_statue",
            domain: .objects,
            firstVisitPrimary: "Figure in meditation posture",
            firstVisitDetail: nil,
            classificationKeywords: ["statue", "sculpture", "figurine", "idol", "deity", "buddha", "religious", "artifact", "effigy", "monk"],
            textKeywords: ["buddha", "meditation"]
        ),
        CatalogEntry(
            temporarySubjectKey: "device_printer_zebra",
            domain: .electronics,
            firstVisitPrimary: "Zebra ZP505",
            firstVisitDetail: "Thermal label printer.\nReady for 4×6 shipping labels.",
            classificationKeywords: ["printer", "printing", "label", "office", "equipment", "machine"],
            textKeywords: ["zebra", "zp505", "zp 505", "thermal", "printer"]
        ),
        CatalogEntry(
            temporarySubjectKey: "device_computer_macmini",
            domain: .electronics,
            firstVisitPrimary: "Mac mini M4",
            firstVisitDetail: "Compact desktop.\nSilent when idle.",
            classificationKeywords: ["computer", "desktop", "mac", "minicomputer", "electronics", "server", "workstation", "personal computer", "pc"],
            textKeywords: ["mac mini", "macmini", "apple"]
        ),
        CatalogEntry(
            temporarySubjectKey: "plant_coffea",
            domain: .plants,
            firstVisitPrimary: "New flower buds forming",
            firstVisitDetail: "Likely to open in 4–7 days.\n\nFlowering appears uniform across the upper canopy.",
            classificationKeywords: ["plant", "houseplant", "coffee", "shrub", "vegetation", "tree"],
            textKeywords: ["coffee", "coffea"]
        ),
        CatalogEntry(
            temporarySubjectKey: "art_painting",
            domain: .art,
            firstVisitPrimary: "Light across the canvas",
            firstVisitDetail: nil,
            classificationKeywords: ["painting", "art", "picture", "canvas", "frame", "poster"],
            textKeywords: ["painting", "canvas"]
        ),
        CatalogEntry(
            temporarySubjectKey: "plant_leaf",
            domain: .plants,
            firstVisitPrimary: "Possible early chlorosis",
            firstVisitDetail: "Older leaves affected first.\nCompare with neighboring leaves.",
            classificationKeywords: ["leaf", "foliage", "green", "plant", "herb"],
            textKeywords: ["leaf"]
        ),
        CatalogEntry(
            temporarySubjectKey: "plant_flower",
            domain: .plants,
            firstVisitPrimary: "New flower buds forming",
            firstVisitDetail: "Likely to open in 4–7 days.",
            classificationKeywords: ["flower", "bloom", "blossom", "petal", "floral"],
            textKeywords: ["flower", "bloom", "blossom"]
        )
    ]

    func identify(jpeg: Data, profile: CuriosityProfile) async -> SubjectResolution? {
        #if os(iOS)
        return await Task.detached(priority: .userInitiated) {
            guard
                let image = UIImage(data: jpeg),
                let cgImage = image.cgImage
            else {
                return nil
            }

            let orientation = CGImagePropertyOrientation(image.imageOrientation)
            let handler = VNImageRequestHandler(cgImage: cgImage, orientation: orientation, options: [:])

            let classifications = Self.runClassifications(handler: handler)
            let recognizedText = Self.runTextRecognition(handler: handler)
            let anchor = Self.runSaliencyAnchor(handler: handler) ?? CGPoint(x: 0.5, y: 0.5)

            guard let match = Self.bestMatch(
                catalog: Self.catalog,
                profile: profile,
                classifications: classifications,
                recognizedText: recognizedText
            ) else {
                return nil
            }

            guard match.score >= PerceptionConfiguration.subjectMatchThreshold else {
                return nil
            }

            return SubjectResolution(
                temporarySubjectKey: match.entry.temporarySubjectKey,
                domain: match.entry.domain,
                anchor: anchor,
                matchConfidence: match.score,
                firstVisitPrimary: match.entry.firstVisitPrimary,
                firstVisitDetail: match.entry.firstVisitDetail
            )
        }.value
        #else
        return nil
        #endif
    }

    #if os(iOS)
    private static func bestMatch(
        catalog: [CatalogEntry],
        profile: CuriosityProfile,
        classifications: [(String, Float)],
        recognizedText: [String]
    ) -> (entry: CatalogEntry, score: Float)? {
        let normalizedText = recognizedText.joined(separator: " ").lowercased()
        var best: (entry: CatalogEntry, score: Float)?

        for entry in catalog {
            for keyword in entry.textKeywords where normalizedText.contains(keyword) {
                let score = Float(profile.weight(for: entry.domain)) * 0.95
                if best == nil || score > best!.score {
                    best = (entry, score)
                }
            }
        }

        for (identifier, confidence) in classifications where confidence > 0.05 {
            let normalized = identifier.lowercased().replacingOccurrences(of: "_", with: " ")
            for entry in catalog {
                if entry.classificationKeywords.contains(where: { normalized.contains($0) }) {
                    let score = confidence * Float(profile.weight(for: entry.domain))
                    if best == nil || score > best!.score {
                        best = (entry, score)
                    }
                }
            }
        }

        return best
    }

    private static func runClassifications(handler: VNImageRequestHandler) -> [(String, Float)] {
        var output: [(String, Float)] = []
        let request = VNClassifyImageRequest { request, _ in
            output = (request.results as? [VNClassificationObservation])?
                .prefix(12)
                .map { ($0.identifier, $0.confidence) } ?? []
        }
        try? handler.perform([request])
        return output
    }

    private static func runTextRecognition(handler: VNImageRequestHandler) -> [String] {
        var output: [String] = []
        let request = VNRecognizeTextRequest { request, _ in
            output = (request.results as? [VNRecognizedTextObservation])?
                .compactMap { $0.topCandidates(1).first?.string } ?? []
        }
        request.recognitionLevel = .fast
        try? handler.perform([request])
        return output
    }

    private static func runSaliencyAnchor(handler: VNImageRequestHandler) -> CGPoint? {
        var anchor: CGPoint?
        let request = VNGenerateAttentionBasedSaliencyImageRequest { request, _ in
            guard
                let observation = request.results?.first as? VNSaliencyImageObservation,
                let salientObject = observation.salientObjects?.first
            else {
                return
            }
            anchor = VisionGeometry.anchor(fromVisionBounds: salientObject.boundingBox)
        }
        try? handler.perform([request])
        return anchor
    }
    #endif
}

#if os(iOS)
private extension CGImagePropertyOrientation {
    init(_ orientation: UIImage.Orientation) {
        switch orientation {
        case .up: self = .up
        case .upMirrored: self = .upMirrored
        case .down: self = .down
        case .downMirrored: self = .downMirrored
        case .left: self = .left
        case .leftMirrored: self = .leftMirrored
        case .right: self = .right
        case .rightMirrored: self = .rightMirrored
        @unknown default: self = .right
        }
    }
}
#endif
