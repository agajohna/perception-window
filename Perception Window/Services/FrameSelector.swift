//
//  FrameSelector.swift
//  Perception Window
//

import Foundation

/// Collects candidate frames during a hold and selects the best one — no API calls.
struct FrameSelector {
    private struct Candidate {
        let jpeg: Data
        let quality: FrameQualityScore
    }

    private var best: Candidate?

    mutating func reset() {
        best = nil
    }

    mutating func consider(_ jpeg: Data) {
        let quality = FrameQuality.assess(jpeg)
        guard quality.isAcceptable else { return }

        if best == nil || quality.score > best!.quality.score {
            best = Candidate(jpeg: jpeg, quality: quality)
        }
    }

    func selectedJPEG() -> Data? {
        best?.jpeg
    }

    var hasAcceptableFrame: Bool {
        best != nil
    }
}
