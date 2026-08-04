//
//  VirtualEyeGeometry.swift
//  Perception Window
//

import ARKit
import CoreGraphics
import UIKit
import simd

#if os(iOS)

enum VirtualEyeGeometry {
    struct ScreenSample {
        var displayUV: SIMD2<Float>
        var cameraUV: SIMD2<Float>
        var isValid: Bool
    }

    struct SampleGridResult {
        var samples: [ScreenSample]
        /// Largest motion-correction UV delta on the grid, in screen pixels.
        var maxUVShiftPixels: Float
        var reprojectionHits: Int
        var gridPointCount: Int
        /// Per-grid `projectedUV - passthroughUV` before lock subtraction.
        var reprojectionDeltas: [SIMD2<Float>]
    }

    /// Capture reprojection deltas at lock/recenter for motion-relative warp.
    static func captureReprojectionDeltas(
        snapshot: ARFrameSnapshot,
        reference: SceneReference,
        gridSize: Int
    ) -> [SIMD2<Float>] {
        makeSampleGrid(
            snapshot: snapshot,
            reference: reference,
            gridSize: gridSize,
            exaggerationGain: 1,
            lockBaselineDeltas: nil
        ).reprojectionDeltas
    }

    /// Phone + head parallax for the fullscreen warp path.
    static func combinedParallaxUVOffset(
        snapshot: ARFrameSnapshot,
        lockCameraPosition: SIMD3<Float>,
        sceneDepthMeters: Float,
        viewerPose: ViewerPoseEstimate?,
        lockedViewerLateral: SIMD2<Float>?,
        exaggerationGain: Float = 1.0
    ) -> SIMD2<Float> {
        var offset = planarParallaxUVOffset(
            snapshot: snapshot,
            lockCameraPosition: lockCameraPosition,
            sceneDepthMeters: sceneDepthMeters,
            exaggerationGain: exaggerationGain
        )

        guard PerceptionConfiguration.glassViewViewerPoseEnabled,
              let viewerPose,
              viewerPose.isValid,
              let lockedViewerLateral else {
            return offset
        }

        offset += headParallaxUVOffset(
            snapshot: snapshot,
            viewerPose: viewerPose,
            lockedViewerLateral: lockedViewerLateral
        )
        return saturateParallaxOffset(offset)
    }

    /// Head shift relative to phone since lock — opposite sign to phone motion convention.
    static func headParallaxUVOffset(
        snapshot: ARFrameSnapshot,
        viewerPose: ViewerPoseEstimate,
        lockedViewerLateral: SIMD2<Float>
    ) -> SIMD2<Float> {
        let headDelta = viewerPose.lateralOffsetMeters - lockedViewerLateral
        let eyeDistance = max(viewerPose.eyeToScreenDistanceMeters, 0.25)
        let width = Float(snapshot.viewportSize.width)
        let height = Float(snapshot.viewportSize.height)
        let focalX = snapshot.projectionMatrix[0][0] * width * 0.5
        let focalY = snapshot.projectionMatrix[1][1] * height * 0.5
        let strength = max(PerceptionConfiguration.glassViewHeadParallaxStrength, 0)

        return SIMD2(
            -headDelta.x / eyeDistance * focalX / width,
            headDelta.y / eyeDistance * focalY / height
        ) * strength
    }

    /// Uniform 2D parallax for a planar scene — stable, no mesh folding.
    static func planarParallaxUVOffset(
        snapshot: ARFrameSnapshot,
        lockCameraPosition: SIMD3<Float>,
        sceneDepthMeters: Float,
        exaggerationGain: Float = 1.0
    ) -> SIMD2<Float> {
        let delta = snapshot.cameraTransform.position - lockCameraPosition
        let configuredDepth = PerceptionConfiguration.scenePlaneDepthMeters
        // Prefer the tuned working distance when AR plane depth is farther (weakens parallax).
        let depth = max(
            min(sceneDepthMeters, configuredDepth),
            PerceptionConfiguration.scenePlaneDepthMinimumMeters
        )
        let right = snapshot.cameraTransform.right
        let up = snapshot.cameraTransform.up
        let width = Float(snapshot.viewportSize.width)
        let height = Float(snapshot.viewportSize.height)
        let focalX = snapshot.projectionMatrix[0][0] * width * 0.5
        let focalY = snapshot.projectionMatrix[1][1] * height * 0.5
        let gain = max(exaggerationGain, 1.0)
        let strength = max(PerceptionConfiguration.glassViewMotionParallaxStrength, 0)

        return saturateParallaxOffset(
            SIMD2(
                simd_dot(delta, right) / depth * focalX / width,
                -simd_dot(delta, up) / depth * focalY / height
            ) * gain * strength
        )
    }

    /// Soft-limits large UV shifts so clamp-to-edge sampling does not streak.
    private static func saturateParallaxOffset(_ offset: SIMD2<Float>) -> SIMD2<Float> {
        let maxUV = PerceptionConfiguration.glassViewMaxParallaxUVOffset
        guard maxUV > 0 else { return offset }

        let magnitude = simd_length(offset)
        guard magnitude > 1e-6 else { return offset }

        let scaledMagnitude = tanh(magnitude / maxUV) * maxUV
        return offset * (scaledMagnitude / magnitude)
    }

    /// Magnification so angular scale matches looking through the display aperture.
    static func windowMagnification(
        snapshot: ARFrameSnapshot,
        eyeDistanceMeters: Float
    ) -> Float {
        guard PerceptionConfiguration.glassViewWindowScaleEnabled else { return 1.0 }

        let profile = DeviceOpticalProfile.current
        let eyeDistance = max(eyeDistanceMeters, 0.25)
        let windowHalfWidth = profile.displayWidthMeters * 0.5
        let windowTangent = tan(windowHalfWidth / eyeDistance)

        let cameraTangent = 1.0 / max(snapshot.projectionMatrix[0][0], 0.01)
        guard windowTangent > 1e-4 else { return 1.0 }

        let physicalMagnification = cameraTangent / windowTangent
        let strength = min(max(PerceptionConfiguration.glassViewWindowScaleStrength, 0), 1)
        let blended = 1.0 + (physicalMagnification - 1.0) * strength
        return min(blended, PerceptionConfiguration.glassViewWindowScaleMaximum)
    }

    static func makePlanarMotionParallaxGrid(
        snapshot: ARFrameSnapshot,
        lockCameraPosition: SIMD3<Float>,
        sceneDepthMeters: Float,
        gridSize: Int,
        exaggerationGain: Float = 1.0
    ) -> SampleGridResult {
        let inverseDisplay = snapshot.inverseDisplayTransform

        let uvOffset = planarParallaxUVOffset(
            snapshot: snapshot,
            lockCameraPosition: lockCameraPosition,
            sceneDepthMeters: sceneDepthMeters,
            exaggerationGain: exaggerationGain
        )

        var samples: [ScreenSample] = []
        var reprojectionDeltas: [SIMD2<Float>] = []
        samples.reserveCapacity(gridSize * gridSize)
        reprojectionDeltas.reserveCapacity(gridSize * gridSize)

        var reprojectionHits = 0
        for row in 0..<gridSize {
            for column in 0..<gridSize {
                let u = Float(column) / Float(gridSize - 1)
                let v = Float(row) / Float(gridSize - 1)

                guard let passthrough = passthroughUV(
                    u: u,
                    v: v,
                    inverseDisplayTransform: inverseDisplay
                ) else {
                    samples.append(ScreenSample(displayUV: SIMD2(u, v), cameraUV: .zero, isValid: false))
                    reprojectionDeltas.append(.zero)
                    continue
                }

                let shifted = passthrough + uvOffset
                let cameraUV = SIMD2(
                    min(max(shifted.x, 0), 1),
                    min(max(shifted.y, 0), 1)
                )
                samples.append(ScreenSample(displayUV: SIMD2(u, v), cameraUV: cameraUV, isValid: true))
                reprojectionDeltas.append(uvOffset)
                reprojectionHits &+= 1
            }
        }

        let shiftPixels = hypot(
            uvOffset.x * Float(snapshot.viewportSize.width),
            uvOffset.y * Float(snapshot.viewportSize.height)
        )
        return SampleGridResult(
            samples: samples,
            maxUVShiftPixels: shiftPixels,
            reprojectionHits: reprojectionHits,
            gridPointCount: gridSize * gridSize,
            reprojectionDeltas: reprojectionDeltas
        )
    }

    struct SceneReference {
        var virtualEyeWorld: SIMD3<Float>
        var planeNormal: SIMD3<Float>
        var anchorCameraPosition: SIMD3<Float>
        var sceneDepthMeters: Float

        var planeOrigin: SIMD3<Float> {
            anchorCameraPosition + planeNormal * sceneDepthMeters
        }
    }

    static func passthroughGrid(
        inverseDisplayTransform: CGAffineTransform,
        gridSize: Int
    ) -> [ScreenSample] {
        var samples: [ScreenSample] = []
        samples.reserveCapacity(gridSize * gridSize)

        for row in 0..<gridSize {
            for column in 0..<gridSize {
                let u = Float(column) / Float(gridSize - 1)
                let v = Float(row) / Float(gridSize - 1)

                let cameraUV = passthroughUV(u: u, v: v, inverseDisplayTransform: inverseDisplayTransform)
                    ?? SIMD2(u, v)

                samples.append(
                    ScreenSample(displayUV: SIMD2(u, v), cameraUV: cameraUV, isValid: true)
                )
            }
        }

        return samples
    }

    static func passthroughGrid(
        frame: ARFrame,
        viewportSize: CGSize,
        gridSize: Int
    ) -> [ScreenSample] {
        let inverseDisplay = frame.displayTransform(
            for: .portrait,
            viewportSize: viewportSize
        ).inverted()
        return passthroughGrid(inverseDisplayTransform: inverseDisplay, gridSize: gridSize)
    }

    static func lockReference(from frame: ARFrame) -> SceneReference {
        let profile = DeviceOpticalProfile.current
        let cameraTransform = frame.camera.transform
        let cameraForward = cameraTransform.forward

        let eyeLocal = profile.virtualEyeOffsetFromCamera(
            eyeDistanceMeters: PerceptionConfiguration.virtualEyeDistanceMeters
        )
        let virtualEyeWorld = cameraTransform.transformPoint(eyeLocal)

        let depth = PerceptionConfiguration.scenePlaneDepthMeters

        return SceneReference(
            virtualEyeWorld: virtualEyeWorld,
            planeNormal: cameraForward,
            anchorCameraPosition: cameraTransform.position,
            sceneDepthMeters: depth
        )
    }

    /// Sensor-fused scene reference — eye and plane locked in world until TrueDepth updates the eye.
    static func sceneReference(
        from state: PerceptionState,
        snapshot: ARFrameSnapshot,
        lockedPlaneAnchor: SIMD3<Float>,
        lockedVirtualEyeWorld: SIMD3<Float>,
        lockedPlaneNormal: SIMD3<Float>,
        profile: DeviceOpticalProfile = DeviceOpticalProfile.current
    ) -> SceneReference {
        let virtualEyeWorld: SIMD3<Float>
        if state.viewerPose.isValid {
            virtualEyeWorld = state.predictedDevicePose.transformPoint(state.viewerPose.eyeMidpointDevice)
        } else {
            virtualEyeWorld = lockedVirtualEyeWorld
        }

        let planeNormal: SIMD3<Float>
        if state.viewerPose.isValid {
            planeNormal = state.sceneDepth.planeNormal
        } else {
            planeNormal = lockedPlaneNormal
        }

        return SceneReference(
            virtualEyeWorld: virtualEyeWorld,
            planeNormal: planeNormal,
            anchorCameraPosition: lockedPlaneAnchor,
            sceneDepthMeters: state.sceneDepth.dominantPlaneDepthMeters
        )
    }

    static func referenceByUpdatingDepth(
        _ reference: SceneReference,
        sceneDepthMeters: Float
    ) -> SceneReference {
        var updated = reference
        updated.sceneDepthMeters = sceneDepthMeters
        return updated
    }

    static func sampleGrid(
        snapshot: ARFrameSnapshot,
        reference: SceneReference,
        gridSize: Int,
        exaggerationGain: Float = 1.0
    ) -> [ScreenSample] {
        makeSampleGrid(
            snapshot: snapshot,
            reference: reference,
            gridSize: gridSize,
            exaggerationGain: exaggerationGain
        ).samples
    }

    static func makeSampleGrid(
        snapshot: ARFrameSnapshot,
        reference: SceneReference,
        gridSize: Int,
        exaggerationGain: Float = 1.0,
        lockBaselineDeltas: [SIMD2<Float>]? = nil
    ) -> SampleGridResult {
        let cameraTransform = snapshot.cameraTransform
        let right = cameraTransform.right
        let up = cameraTransform.up
        let profile = DeviceOpticalProfile.current
        let screenCenterWorld = cameraTransform.transformPoint(profile.screenCenterOffsetFromCameraMeters)
        let screenWidth = profile.displayWidthMeters
        let screenHeight = profile.displayHeightMeters
        let inverseDisplay = snapshot.inverseDisplayTransform
        let gain = max(exaggerationGain, 1.0)
        var maxUVShiftPixels: Float = 0
        var reprojectionHits = 0
        let gridPointCount = gridSize * gridSize

        var samples: [ScreenSample] = []
        var reprojectionDeltas: [SIMD2<Float>] = []
        samples.reserveCapacity(gridSize * gridSize)
        reprojectionDeltas.reserveCapacity(gridSize * gridSize)

        var sampleIndex = 0
        for row in 0..<gridSize {
            for column in 0..<gridSize {
                let u = Float(column) / Float(gridSize - 1)
                let v = Float(row) / Float(gridSize - 1)

                guard let passthrough = passthroughUV(
                    u: u,
                    v: v,
                    inverseDisplayTransform: inverseDisplay
                ) else {
                    samples.append(ScreenSample(displayUV: SIMD2(u, v), cameraUV: .zero, isValid: false))
                    reprojectionDeltas.append(.zero)
                    sampleIndex &+= 1
                    continue
                }

                let offsetX = (u - 0.5) * screenWidth
                let offsetY = (0.5 - v) * screenHeight
                let screenPointWorld = screenCenterWorld + right * offsetX + up * offsetY

                let rayOrigin = reference.virtualEyeWorld
                let rayDirection = simd_normalize(screenPointWorld - rayOrigin)

                var viewpointDelta = SIMD2<Float>(0, 0)
                if
                    let worldPoint = intersectRay(
                        origin: rayOrigin,
                        direction: rayDirection,
                        planeOrigin: reference.planeOrigin,
                        planeNormal: reference.planeNormal
                    ),
                    let projectedUV = snapshot.imageUV(for: worldPoint)
                {
                    viewpointDelta = projectedUV - passthrough
                    reprojectionHits &+= 1
                }

                reprojectionDeltas.append(viewpointDelta)

                let baseline = lockBaselineDeltas?[sampleIndex] ?? SIMD2(0, 0)
                let warpDelta = viewpointDelta - baseline
                let shifted = passthrough + warpDelta * gain
                let cameraUV = SIMD2(
                    min(max(shifted.x, 0), 1),
                    min(max(shifted.y, 0), 1)
                )

                let shiftPixels = hypot(
                    warpDelta.x * Float(snapshot.viewportSize.width),
                    warpDelta.y * Float(snapshot.viewportSize.height)
                )
                maxUVShiftPixels = max(maxUVShiftPixels, shiftPixels)

                samples.append(ScreenSample(displayUV: SIMD2(u, v), cameraUV: cameraUV, isValid: true))
                sampleIndex &+= 1
            }
        }

        return SampleGridResult(
            samples: samples,
            maxUVShiftPixels: maxUVShiftPixels,
            reprojectionHits: reprojectionHits,
            gridPointCount: gridPointCount,
            reprojectionDeltas: reprojectionDeltas
        )
    }

    /// Phone translation since lock → opposite image shift (unused; reprojection handles motion).
    private static func motionParallaxOffset(
        snapshot: ARFrameSnapshot,
        anchorCameraPosition: SIMD3<Float>,
        sceneDepthMeters: Float
    ) -> SIMD2<Float> {
        let delta = snapshot.cameraTransform.position - anchorCameraPosition
        let depth = max(sceneDepthMeters, 0.25)
        let right = snapshot.cameraTransform.right
        let up = snapshot.cameraTransform.up
        let strength = PerceptionConfiguration.glassViewMotionParallaxStrength

        return SIMD2(
            -simd_dot(delta, right) / depth * strength,
            simd_dot(delta, up) / depth * strength
        )
    }

    private static func exaggeratedUV(
        reprojectionUV: SIMD2<Float>,
        passthroughUV: SIMD2<Float>?,
        gain: Float
    ) -> SIMD2<Float> {
        guard gain > 1, let passthroughUV else { return reprojectionUV }
        let delta = reprojectionUV - passthroughUV
        let scaled = passthroughUV + delta * gain
        return SIMD2(
            min(max(scaled.x, 0), 1),
            min(max(scaled.y, 0), 1)
        )
    }

    static func sampleGrid(
        frame: ARFrame,
        reference: SceneReference,
        viewportSize: CGSize,
        gridSize: Int
    ) -> [ScreenSample] {
        sampleGrid(
            snapshot: ARFrameSnapshot.make(from: frame, viewportSize: viewportSize),
            reference: reference,
            gridSize: gridSize
        )
    }

    /// Standard full-screen camera mapping when reprojection fails for a grid point.
    private static func passthroughUV(
        u: Float,
        v: Float,
        inverseDisplayTransform: CGAffineTransform
    ) -> SIMD2<Float>? {
        ARFrameSnapshot.imageUV(
            fromViewNormalized: CGPoint(x: CGFloat(u), y: CGFloat(v)),
            inverseDisplayTransform: inverseDisplayTransform
        )
    }

    private static func intersectRay(
        origin: SIMD3<Float>,
        direction: SIMD3<Float>,
        planeOrigin: SIMD3<Float>,
        planeNormal: SIMD3<Float>
    ) -> SIMD3<Float>? {
        let denominator = simd_dot(direction, planeNormal)
        guard abs(denominator) > 1e-5 else { return nil }

        let planeDistance = simd_dot(planeOrigin - origin, planeNormal) / denominator
        guard planeDistance > 0.01 else { return nil }

        return origin + direction * planeDistance
    }
}

extension simd_float4x4 {
    func transformPoint(_ point: SIMD3<Float>) -> SIMD3<Float> {
        let transformed = self * SIMD4(point, 1)
        return SIMD3(transformed.x, transformed.y, transformed.z)
    }

    var position: SIMD3<Float> {
        SIMD3(columns.3.x, columns.3.y, columns.3.z)
    }

    var right: SIMD3<Float> {
        SIMD3(columns.0.x, columns.0.y, columns.0.z)
    }

    var up: SIMD3<Float> {
        SIMD3(columns.1.x, columns.1.y, columns.1.z)
    }

    var forward: SIMD3<Float> {
        -SIMD3(columns.2.x, columns.2.y, columns.2.z)
    }
}

#endif
