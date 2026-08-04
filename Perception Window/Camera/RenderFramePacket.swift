//
//  RenderFramePacket.swift
//  Perception Window
//

import CoreVideo

#if os(iOS)

/// Copied camera data safe to use after the ARSession delegate returns.
struct RenderFramePacket {
    let pixelBuffer: CVPixelBuffer
    let snapshot: ARFrameSnapshot
    let timestamp: TimeInterval
}

#endif
