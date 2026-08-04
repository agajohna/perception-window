//
//  ARFrameFusionInput.swift
//  Perception Window
//
//  Snapshot of ARFrame data copied synchronously — safe to use off the delegate callback.
//

import ARKit
import CoreVideo
import simd

#if os(iOS)

struct ARFrameFusionInput: Sendable {
    let timestamp: TimeInterval
    let trackingState: ARCamera.TrackingState
    let snapshot: ARFrameSnapshot
    let copiedWideBuffer: CVPixelBuffer
    let featurePoints: [SIMD3<Float>]
    let planes: [PlaneSnapshot]
    let intrinsics: CameraIntrinsics

    struct PlaneSnapshot: Sendable {
        let position: SIMD3<Float>
        let normal: SIMD3<Float>
        let width: Float
        let height: Float
        let alignment: UInt8
    }

    static func capture(from frame: ARFrame, viewportSize: CGSize, copiedBuffer: CVPixelBuffer) -> ARFrameFusionInput {
        let points = frame.rawFeaturePoints?.points ?? []
        let planes = frame.anchors.compactMap { anchor -> PlaneSnapshot? in
            guard let plane = anchor as? ARPlaneAnchor else { return nil }
            let transform = plane.transform
            return PlaneSnapshot(
                position: SIMD3(transform.columns.3.x, transform.columns.3.y, transform.columns.3.z),
                normal: simd_normalize(SIMD3(transform.columns.2.x, transform.columns.2.y, transform.columns.2.z)),
                width: plane.planeExtent.width,
                height: plane.planeExtent.height,
                alignment: plane.alignment == .horizontal ? 0 : 1
            )
        }

        return ARFrameFusionInput(
            timestamp: frame.timestamp,
            trackingState: frame.camera.trackingState,
            snapshot: ARFrameSnapshot.make(from: frame, viewportSize: viewportSize),
            copiedWideBuffer: copiedBuffer,
            featurePoints: Array(points.prefix(256)),
            planes: planes,
            intrinsics: CameraIntrinsics.make(from: frame)
        )
    }
}

#endif
