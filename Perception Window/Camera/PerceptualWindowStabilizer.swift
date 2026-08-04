//
//  PerceptualWindowStabilizer.swift
//  Perception Window
//

import CoreGraphics
import CoreMotion
import Foundation
import Observation

#if os(iOS)

/// Keeps the preview aligned with the user's line of sight instead of the camera sensor.
///
/// A phone screen shows what the rear camera sees. Glass shows what your eyes see through
/// the pane. Those viewpoints differ (camera offset, parallax). This applies a continuous
/// transform so small phone movements don't break edge alignment with the real world.
@Observable
final class PerceptualWindowStabilizer {
    private let motionManager = CMMotionManager()
    private var referenceAttitude: CMAttitude?
    private var isRunning = false

    private(set) var previewTransform: CGAffineTransform = .identity

    func start() {
        guard PerceptionConfiguration.perceptualWindowStabilizationEnabled else { return }
        guard motionManager.isDeviceMotionAvailable, !isRunning else { return }

        referenceAttitude = nil
        isRunning = true
        motionManager.deviceMotionUpdateInterval = 1.0 / 60.0
        motionManager.startDeviceMotionUpdates(using: .xArbitraryZVertical, to: .main) { [weak self] motion, _ in
            guard let self, let motion else { return }
            self.apply(motion)
        }
    }

    func stop() {
        guard isRunning else { return }
        motionManager.stopDeviceMotionUpdates()
        isRunning = false
        referenceAttitude = nil
        previewTransform = baselineTransform()
    }

    /// Re-lock when the user finds a moment where edges align naturally.
    func recenterLineOfSight() {
        referenceAttitude = nil
    }

    private func apply(_ motion: CMDeviceMotion) {
        if referenceAttitude == nil {
            referenceAttitude = motion.attitude.copy() as? CMAttitude
            previewTransform = baselineTransform()
            return
        }

        let delta = motion.attitude.copy() as! CMAttitude
        delta.multiply(byInverseOf: referenceAttitude!)

        let strength = PerceptionConfiguration.gazeParallaxStrength
        // Portrait hold: pitch shifts vertical gaze line, roll shifts horizontal.
        let compensatedX = PerceptionConfiguration.cameraEyeHorizontalOffset
            - CGFloat(delta.roll) * strength
        let compensatedY = PerceptionConfiguration.cameraEyeVerticalOffset
            + CGFloat(delta.pitch) * strength

        previewTransform = composedTransform(translationX: compensatedX, translationY: compensatedY)
    }

    private func baselineTransform() -> CGAffineTransform {
        composedTransform(
            translationX: PerceptionConfiguration.cameraEyeHorizontalOffset,
            translationY: PerceptionConfiguration.cameraEyeVerticalOffset
        )
    }

    private func composedTransform(translationX: CGFloat, translationY: CGFloat) -> CGAffineTransform {
        let overscan = PerceptionConfiguration.perceptualPreviewOverscan
        return CGAffineTransform(scaleX: overscan, y: overscan)
            .translatedBy(x: translationX / overscan, y: translationY / overscan)
    }
}

#else

@Observable
final class PerceptualWindowStabilizer {
    private(set) var previewTransform: CGAffineTransform = .identity

    func start() {}
    func stop() {}
    func recenterLineOfSight() {}
}

#endif
