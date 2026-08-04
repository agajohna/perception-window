//
//  SceneDepthFusion.swift
//  Perception Window
//
//  Dynamic dominant-plane depth from ARKit features, planes, and parallax.
//

import ARKit
import simd

#if os(iOS)

final class SceneDepthFusion {
    private let parallaxEstimator = PlaneDepthEstimator(
        initialDepthMeters: PerceptionConfiguration.scenePlaneDepthMeters
    )
    private let lock = NSLock()

    private var filteredDepth: Float = PerceptionConfiguration.scenePlaneDepthMeters
    private var filteredNormal = SIMD3<Float>(0, 0, -1)
    private var lastSource: SceneDepthEstimate.Source = .fixed

    func reset(from snapshot: ARFrameSnapshot) {
        parallaxEstimator.reset(from: snapshot, initialDepthMeters: PerceptionConfiguration.scenePlaneDepthMeters)
        lock.lock()
        filteredDepth = PerceptionConfiguration.scenePlaneDepthMeters
        filteredNormal = snapshot.cameraTransform.forward
        lastSource = .fixed
        lock.unlock()
    }

    func resetToDefaults() {
        parallaxEstimator.resetToInitialDepth(PerceptionConfiguration.scenePlaneDepthMeters)
        lock.lock()
        filteredDepth = PerceptionConfiguration.scenePlaneDepthMeters
        lastSource = .fixed
        lock.unlock()
    }

    func update(from input: ARFrameFusionInput) -> SceneDepthEstimate {
        let cameraTransform = input.snapshot.cameraTransform
        let forward = cameraTransform.forward

        parallaxEstimator.update(from: input.snapshot)
        let parallaxDepth = parallaxEstimator.sceneDepthMeters

        let featureEstimate = estimateFromFeaturePoints(
            points: input.featurePoints,
            cameraTransform: cameraTransform
        )
        let planeEstimate = estimateFromDetectedPlanes(
            planes: input.planes,
            cameraTransform: cameraTransform
        )

        var candidateDepth = parallaxDepth
        var candidateConfidence: Float = 0.35
        var source: SceneDepthEstimate.Source = .parallax

        if let featureEstimate {
            candidateDepth = featureEstimate.depth
            candidateConfidence = max(candidateConfidence, featureEstimate.confidence)
            source = .featurePoints
        }

        if let planeEstimate,
           planeEstimate.depth >= PerceptionConfiguration.scenePlaneDepthMinimumMeters,
           planeEstimate.confidence > candidateConfidence {
            candidateDepth = planeEstimate.depth
            candidateConfidence = planeEstimate.confidence
            source = .arPlane
        }

        if PerceptionConfiguration.planeDepthSelfTuningEnabled, source == .parallax || source == .featurePoints {
            candidateDepth = mix(filteredDepth, parallaxDepth, t: 0.25)
            source = .fused
            candidateConfidence = max(candidateConfidence, 0.45)
        }

        lock.lock()
        let alpha = PerceptionConfiguration.sceneDepthFilterAlpha
        filteredDepth = mix(filteredDepth, candidateDepth, t: alpha)
        filteredNormal = simd_normalize(mix(filteredNormal, forward, t: 0.15))
        lastSource = source
        var depth = filteredDepth
        if depth < PerceptionConfiguration.sceneDepthPreferredMinimumMeters {
            depth = mix(depth, PerceptionConfiguration.scenePlaneDepthMeters, t: 0.55)
            if source == .arPlane { lastSource = .parallax }
        }
        if depth > PerceptionConfiguration.sceneDepthPreferredMaximumMeters {
            depth = mix(depth, PerceptionConfiguration.scenePlaneDepthMeters, t: 0.65)
        }
        let normal = filteredNormal
        let finalSource = lastSource
        lock.unlock()

        return SceneDepthEstimate(
            dominantPlaneDepthMeters: depth,
            planeNormal: normal,
            confidence: candidateConfidence,
            source: finalSource
        )
    }

    private struct DepthCandidate {
        var depth: Float
        var confidence: Float
    }

    private func estimateFromFeaturePoints(
        points: [SIMD3<Float>],
        cameraTransform: simd_float4x4
    ) -> DepthCandidate? {
        guard !points.isEmpty else { return nil }

        let cameraPosition = cameraTransform.position
        let forward = cameraTransform.forward
        let right = cameraTransform.right
        let up = cameraTransform.up

        var depths: [Float] = []
        depths.reserveCapacity(min(points.count, 256))

        for point in points {
            let delta = point - cameraPosition
            let depth = simd_dot(delta, forward)
            guard depth > PerceptionConfiguration.scenePlaneDepthMinimumMeters,
                  depth < PerceptionConfiguration.scenePlaneDepthMaximumMeters else { continue }

            let lateralRight = abs(simd_dot(delta, right))
            let lateralUp = abs(simd_dot(delta, up))
            guard lateralRight < 0.45, lateralUp < 0.45 else { continue }

            depths.append(depth)
            if depths.count >= 128 { break }
        }

        guard depths.count >= 8 else { return nil }

        depths.sort()
        let median = depths[depths.count / 2]
        let confidence = min(0.35 + Float(depths.count) / 256.0, 0.75)
        return DepthCandidate(depth: median, confidence: confidence)
    }

    private func estimateFromDetectedPlanes(
        planes: [ARFrameFusionInput.PlaneSnapshot],
        cameraTransform: simd_float4x4
    ) -> DepthCandidate? {
        guard PerceptionConfiguration.glassViewPlaneDetectionEnabled else { return nil }

        let cameraPosition = cameraTransform.position
        let forward = cameraTransform.forward

        var bestDepth: Float?
        var bestConfidence: Float = 0

        for plane in planes {
            let depth = abs(simd_dot(plane.position - cameraPosition, forward))
            guard depth > PerceptionConfiguration.scenePlaneDepthMinimumMeters,
                  depth < PerceptionConfiguration.scenePlaneDepthMaximumMeters else { continue }

            let isVertical = plane.alignment == 1
            let alignmentConfidence: Float = isVertical ? 0.72 : 0.48
            let sizeConfidence = min((plane.width + plane.height) * 0.15, 0.25)
            var confidence = alignmentConfidence + sizeConfidence

            // Deprioritize close horizontal surfaces (desk/floor).
            if !isVertical, depth < PerceptionConfiguration.sceneDepthPreferredMinimumMeters {
                confidence *= 0.55
            }

            if confidence > bestConfidence {
                bestConfidence = confidence
                bestDepth = depth
            }
        }

        guard let bestDepth else { return nil }
        return DepthCandidate(depth: bestDepth, confidence: min(bestConfidence, 0.85))
    }

    private func mix(_ a: Float, _ b: Float, t: Float) -> Float {
        a + (b - a) * t
    }

    private func mix(_ a: SIMD3<Float>, _ b: SIMD3<Float>, t: Float) -> SIMD3<Float> {
        a + (b - a) * t
    }
}

#endif
