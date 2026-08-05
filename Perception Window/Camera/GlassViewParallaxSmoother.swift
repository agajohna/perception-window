//
//  GlassViewParallaxSmoother.swift
//  Perception Window
//
//  Low-pass filters parallax UV and window magnification to suppress VIO / face jitter.
//

import simd

#if os(iOS)

struct GlassViewParallaxSmoother {
    private var smoothedOffset = SIMD2<Float>(0, 0)
    private var smoothedMagnification: Float = 1
    private var hasSample = false

    mutating func reset(to offset: SIMD2<Float> = .zero, magnification: Float = 1) {
        smoothedOffset = offset
        smoothedMagnification = magnification
        hasSample = false
    }

    mutating func apply(
        offset rawOffset: SIMD2<Float>,
        magnification rawMagnification: Float
    ) -> (offset: SIMD2<Float>, magnification: Float) {
        guard PerceptionConfiguration.glassViewParallaxSmoothingEnabled else {
            return (rawOffset, rawMagnification)
        }

        if !hasSample {
            smoothedOffset = rawOffset
            smoothedMagnification = rawMagnification
            hasSample = true
            return (smoothedOffset, smoothedMagnification)
        }

        let delta = simd_length(rawOffset - smoothedOffset)
        let jitterThreshold = PerceptionConfiguration.glassViewParallaxJitterThresholdUV
        let offsetAlpha = delta < jitterThreshold
            ? PerceptionConfiguration.glassViewParallaxSmoothingAlphaStill
            : PerceptionConfiguration.glassViewParallaxSmoothingAlphaMoving

        smoothedOffset = mix(smoothedOffset, rawOffset, t: offsetAlpha)
        smoothedMagnification = mix(
            smoothedMagnification,
            rawMagnification,
            t: PerceptionConfiguration.glassViewWindowScaleSmoothingAlpha
        )

        return (smoothedOffset, smoothedMagnification)
    }
}

private func mix(_ a: SIMD2<Float>, _ b: SIMD2<Float>, t: Float) -> SIMD2<Float> {
    a + (b - a) * t
}

private func mix(_ a: Float, _ b: Float, t: Float) -> Float {
    a + (b - a) * t
}

#endif
