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

    private var bestAcceptable: Candidate?
    /// Fallback when nothing passes strict gates — smooth objects like printers often fail sharpness.
    private var bestEffort: Candidate?

    mutating func reset() {
        bestAcceptable = nil
        bestEffort = nil
    }

    mutating func consider(_ jpeg: Data) {
        let quality = FrameQuality.assess(jpeg)

        if bestEffort == nil || quality.score > bestEffort!.quality.score {
            bestEffort = Candidate(jpeg: jpeg, quality: quality)
        }

        guard quality.isAcceptable else { return }

        if bestAcceptable == nil || quality.score > bestAcceptable!.quality.score {
            bestAcceptable = Candidate(jpeg: jpeg, quality: quality)
        }
    }

    func selectedJPEG(preferStrictQuality: Bool) -> Data? {
        if preferStrictQuality, let bestAcceptable {
            return bestAcceptable.jpeg
        }
        return bestAcceptable?.jpeg ?? bestEffort?.jpeg
    }

    var hasAnyFrame: Bool {
        bestAcceptable != nil || bestEffort != nil
    }
}
