//
//  DemoPerceptionService.swift
//  Perception Window
//

import CoreGraphics
import Foundation
import Vision

#if os(iOS)
import UIKit
#endif

struct DemoPerceptionService {
    private struct DemoSubject {
        let observation: String
        let detail: String?
        let subject: String
        let domain: CuriosityDomain
        let classificationKeywords: [String]
        let textKeywords: [String]
    }

    private struct RankedMatch {
        let subject: DemoSubject
        let score: Float
    }

    private static let catalog: [DemoSubject] = [
        DemoSubject(
            observation: "Figure in meditation posture",
            detail: nil,
            subject: "statue",
            domain: .objects,
            classificationKeywords: [
                "statue", "sculpture", "figurine", "idol", "deity", "buddha",
                "religious", "artifact", "effigy", "monk"
            ],
            textKeywords: ["buddha", "meditation"]
        ),
        DemoSubject(
            observation: "Zebra ZP505",
            detail: "Thermal label printer.\nReady for 4×6 shipping labels.",
            subject: "printer",
            domain: .electronics,
            classificationKeywords: [
                "printer", "printing", "label", "office", "equipment", "machine"
            ],
            textKeywords: ["zebra", "zp505", "zp 505", "thermal", "printer"]
        ),
        DemoSubject(
            observation: "Mac mini M4",
            detail: "Compact desktop.\nSilent when idle.",
            subject: "computer",
            domain: .electronics,
            classificationKeywords: [
                "computer", "desktop", "mac", "minicomputer", "electronics",
                "server", "workstation", "personal computer", "pc"
            ],
            textKeywords: ["mac mini", "macmini", "apple"]
        ),
        DemoSubject(
            observation: "New flower buds forming",
            detail: "Likely to open in 4–7 days.\n\nFlowering appears uniform across the upper canopy.",
            subject: "plant",
            domain: .plants,
            classificationKeywords: [
                "plant", "houseplant", "coffee", "shrub", "vegetation", "tree"
            ],
            textKeywords: ["coffee", "coffea"]
        ),
        DemoSubject(
            observation: "Light across the canvas",
            detail: nil,
            subject: "painting",
            domain: .art,
            classificationKeywords: [
                "painting", "art", "picture", "canvas", "frame", "poster"
            ],
            textKeywords: ["painting", "canvas"]
        ),
        DemoSubject(
            observation: "Possible early chlorosis",
            detail: "Older leaves affected first.\nCompare with neighboring leaves.",
            subject: "leaf",
            domain: .plants,
            classificationKeywords: [
                "leaf", "foliage", "green", "plant", "herb"
            ],
            textKeywords: ["leaf"]
        ),
        DemoSubject(
            observation: "New flower buds forming",
            detail: "Likely to open in 4–7 days.",
            subject: "flower",
            domain: .plants,
            classificationKeywords: [
                "flower", "bloom", "blossom", "petal", "floral"
            ],
            textKeywords: ["flower", "bloom", "blossom"]
        )
    ]

    func perceive(jpeg: Data, profile: CuriosityProfile) async -> AnalysisResult {
        #if os(iOS)
        return await Task.detached(priority: .userInitiated) {
            guard
                let image = UIImage(data: jpeg),
                let cgImage = image.cgImage
            else {
                return AnalysisResult(outcome: .nothingVisible, rawResponse: "")
            }

            let orientation = CGImagePropertyOrientation(image.imageOrientation)
            let handler = VNImageRequestHandler(cgImage: cgImage, orientation: orientation, options: [:])

            let classifications = Self.runClassifications(handler: handler)
            let recognizedText = Self.runTextRecognition(handler: handler)
            let anchor = Self.runSaliencyAnchor(handler: handler) ?? CGPoint(x: 0.5, y: 0.5)

            guard let match = Self.bestAttention(
                catalog: Self.catalog,
                profile: profile,
                classifications: classifications,
                recognizedText: recognizedText
            ) else {
                return AnalysisResult(outcome: .nothingVisible, rawResponse: "")
            }

            let observation = PerceptionObservation(
                primary: match.subject.observation,
                detail: match.subject.detail,
                subject: match.subject.subject,
                domain: match.subject.domain,
                anchor: anchor
            )

            return AnalysisResult(
                outcome: .observation(observation),
                rawResponse: "demo:\(match.subject.subject)"
            )
        }.value
        #else
        return AnalysisResult(outcome: .nothingVisible, rawResponse: "")
        #endif
    }

    #if os(iOS)
    /// One attention at a time — ranked by signal strength and learned curiosity.
    private static func bestAttention(
        catalog: [DemoSubject],
        profile: CuriosityProfile,
        classifications: [(identifier: String, confidence: Float)],
        recognizedText: [String]
    ) -> RankedMatch? {
        let normalizedText = recognizedText.joined(separator: " ").lowercased()
        var matches: [RankedMatch] = []

        for subject in catalog {
            for keyword in subject.textKeywords where normalizedText.contains(keyword) {
                let weighted = Float(profile.weight(for: subject.domain)) * 0.95
                matches.append(RankedMatch(subject: subject, score: weighted))
            }
        }

        for (identifier, confidence) in classifications where confidence > 0.05 {
            let normalized = identifier.lowercased().replacingOccurrences(of: "_", with: " ")
            for subject in catalog {
                if subject.classificationKeywords.contains(where: { normalized.contains($0) }) {
                    let weighted = confidence * Float(profile.weight(for: subject.domain))
                    matches.append(RankedMatch(subject: subject, score: weighted))
                }
            }
        }

        return matches.max(by: { $0.score < $1.score })
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
