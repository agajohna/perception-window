//
//  PlaneDepthEstimator.swift
//  Perception Window
//
//  Stage A2 — nudge scene-plane depth from small lateral phone motion.
//

import ARKit
import simd

#if os(iOS)

final class PlaneDepthEstimator {
    private(set) var sceneDepthMeters: Float
    private var anchorCameraPosition: SIMD3<Float>?
    private var anchorCameraRight: SIMD3<Float>?
    private var lastLateralMeters: Float?

    init(initialDepthMeters: Float) {
        sceneDepthMeters = initialDepthMeters
    }

    func reset(from snapshot: ARFrameSnapshot, initialDepthMeters: Float) {
        sceneDepthMeters = initialDepthMeters
        anchorCameraPosition = snapshot.cameraTransform.position
        anchorCameraRight = snapshot.cameraTransform.right
        lastLateralMeters = 0
    }

    func reset(from frame: ARFrame, initialDepthMeters: Float) {
        sceneDepthMeters = initialDepthMeters
        anchorCameraPosition = frame.camera.transform.position
        anchorCameraRight = frame.camera.transform.right
        lastLateralMeters = 0
    }

    func resetToInitialDepth(_ depth: Float) {
        sceneDepthMeters = depth
        anchorCameraPosition = nil
        anchorCameraRight = nil
        lastLateralMeters = nil
    }

    func update(from snapshot: ARFrameSnapshot) {
        guard PerceptionConfiguration.planeDepthSelfTuningEnabled else { return }
        guard
            let anchorCameraPosition,
            let anchorCameraRight
        else {
            return
        }

        let delta = snapshot.cameraTransform.position - anchorCameraPosition
        let lateral = simd_dot(delta, anchorCameraRight)

        if abs(lateral) > 0.08 {
            self.anchorCameraPosition = snapshot.cameraTransform.position
            lastLateralMeters = 0
            return
        }

        guard abs(lateral) > PerceptionConfiguration.planeDepthMinLateralMotionMeters else { return }

        let previous = lastLateralMeters ?? 0
        let lateralStep = lateral - previous
        lastLateralMeters = lateral
        guard abs(lateralStep) > 0.0005 else { return }

        sceneDepthMeters += lateralStep * PerceptionConfiguration.planeDepthLateralGain
        sceneDepthMeters = min(
            max(sceneDepthMeters, PerceptionConfiguration.scenePlaneDepthMinimumMeters),
            PerceptionConfiguration.scenePlaneDepthMaximumMeters
        )
    }
}

#endif
