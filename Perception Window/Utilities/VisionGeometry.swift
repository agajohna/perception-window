//
//  VisionGeometry.swift
//  Perception Window
//

import CoreGraphics

enum VisionGeometry {
    /// Vision bounding box (origin bottom-left, normalized) → anchor point, origin top-left.
    static func anchor(fromVisionBounds bounds: CGRect) -> CGPoint {
        CGPoint(
            x: bounds.midX,
            y: 1 - bounds.midY
        )
    }
}
