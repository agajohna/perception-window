//
//  ARFrameSnapshot.swift
//  Perception Window
//

import ARKit
import CoreGraphics
import simd

#if os(iOS)

extension CGAffineTransform {
    /// Homogeneous matrix for `float3x3 * float3(viewNorm, 1)` in Metal.
    var asInverseDisplayMatrix: simd_float3x3 {
        simd_float3x3(
            SIMD3(Float(a), Float(b), 0),
            SIMD3(Float(c), Float(d), 0),
            SIMD3(Float(tx), Float(ty), 1)
        )
    }
}

/// Pose and projection data copied synchronously from an `ARFrame` — safe to use after the frame is released.
struct ARFrameSnapshot {
    let cameraTransform: simd_float4x4
    let inverseDisplayTransform: CGAffineTransform
    let viewportSize: CGSize
    let viewMatrix: simd_float4x4
    let projectionMatrix: simd_float4x4

    static func make(from frame: ARFrame, viewportSize: CGSize) -> ARFrameSnapshot {
        ARFrameSnapshot(
            cameraTransform: frame.camera.transform,
            inverseDisplayTransform: frame.displayTransform(
                for: .portrait,
                viewportSize: viewportSize
            ).inverted(),
            viewportSize: viewportSize,
            viewMatrix: frame.camera.viewMatrix(for: .portrait),
            projectionMatrix: frame.camera.projectionMatrix(
                for: .portrait,
                viewportSize: viewportSize,
                zNear: 0.001,
                zFar: 1000
            )
        )
    }

    func imageUV(for worldPoint: SIMD3<Float>) -> SIMD2<Float>? {
        guard let viewNormalized = viewNormalized(for: worldPoint) else { return nil }
        return Self.imageUV(fromViewNormalized: viewNormalized, inverseDisplayTransform: inverseDisplayTransform)
    }

    /// Normalized UIKit view coordinates `(x/width, y/height)`.
    func viewNormalized(for worldPoint: SIMD3<Float>) -> CGPoint? {
        let world = SIMD4<Float>(worldPoint.x, worldPoint.y, worldPoint.z, 1)
        var clip = projectionMatrix * viewMatrix * world
        guard clip.w > 0.0001 else { return nil }

        clip /= clip.w
        let viewportX = (CGFloat(clip.x) + 1) * 0.5 * viewportSize.width
        let viewportY = (1 - CGFloat(clip.y)) * 0.5 * viewportSize.height

        guard viewportX.isFinite, viewportY.isFinite else { return nil }

        return CGPoint(
            x: viewportX / viewportSize.width,
            y: viewportY / viewportSize.height
        )
    }

    static func imageUV(
        fromViewNormalized viewNormalized: CGPoint,
        inverseDisplayTransform: CGAffineTransform
    ) -> SIMD2<Float>? {
        let imageNormalized = viewNormalized.applying(inverseDisplayTransform)
        guard imageNormalized.x.isFinite, imageNormalized.y.isFinite else { return nil }

        return SIMD2(
            min(max(Float(imageNormalized.x), 0), 1),
            min(max(Float(imageNormalized.y), 0), 1)
        )
    }
}

#endif
