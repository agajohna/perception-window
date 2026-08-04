//
//  IMUPoseBridge.swift
//  Perception Window
//
//  High-frequency IMU updates for pose prediction between ARKit frames.
//

import ARKit
import CoreMotion
import simd

#if os(iOS)

final class IMUPoseBridge {
    private let motionManager = CMMotionManager()
    private let queue = OperationQueue()
    private let lock = NSLock()

    private var referenceAttitude: CMAttitude?
    private var lastARKitTransform = matrix_identity_float4x4
    private var lastARKitTimestamp: TimeInterval = 0
    private var latestAttitude: CMAttitude?
    private var isRunning = false

    func start() {
        guard PerceptionConfiguration.glassViewIMUPredictionEnabled else { return }
        guard motionManager.isDeviceMotionAvailable, !isRunning else { return }

        referenceAttitude = nil
        isRunning = true
        motionManager.deviceMotionUpdateInterval = 1.0 / 120.0
        motionManager.startDeviceMotionUpdates(using: .xArbitraryZVertical, to: queue) { [weak self] motion, _ in
            guard let self, let motion else { return }
            self.lock.lock()
            self.latestAttitude = motion.attitude
            self.lock.unlock()
        }
    }

    func stop() {
        guard isRunning else { return }
        motionManager.stopDeviceMotionUpdates()
        isRunning = false
        lock.lock()
        referenceAttitude = nil
        latestAttitude = nil
        lock.unlock()
    }

    func ingestARKitTransform(_ transform: simd_float4x4, timestamp: TimeInterval) {
        lock.lock()
        lastARKitTransform = transform
        lastARKitTimestamp = timestamp
        if referenceAttitude == nil {
            referenceAttitude = latestAttitude?.copy() as? CMAttitude
        }
        lock.unlock()
    }

    func predictedTransform() -> (transform: simd_float4x4, applied: Bool) {
        guard PerceptionConfiguration.glassViewIMUPredictionEnabled else {
            return (lastARKitTransform, false)
        }

        lock.lock()
        defer { lock.unlock() }

        guard
            let referenceAttitude,
            let currentAttitude = latestAttitude?.copy() as? CMAttitude
        else {
            return (lastARKitTransform, false)
        }

        let delta = currentAttitude.copy() as! CMAttitude
        delta.multiply(byInverseOf: referenceAttitude)

        let predicted = applyRotationDelta(
            deltaRotation: deltaRotationMatrix(from: delta),
            to: lastARKitTransform
        )
        return (predicted, true)
    }

    private func deltaRotationMatrix(from attitude: CMAttitude) -> simd_float3x3 {
        let matrix = attitude.rotationMatrix
        return simd_float3x3(
            SIMD3(Float(matrix.m11), Float(matrix.m12), Float(matrix.m13)),
            SIMD3(Float(matrix.m21), Float(matrix.m22), Float(matrix.m23)),
            SIMD3(Float(matrix.m31), Float(matrix.m32), Float(matrix.m33))
        )
    }

    private func applyRotationDelta(deltaRotation: simd_float3x3, to transform: simd_float4x4) -> simd_float4x4 {
        var rotation = simd_float3x3(
            SIMD3(transform.columns.0.x, transform.columns.0.y, transform.columns.0.z),
            SIMD3(transform.columns.1.x, transform.columns.1.y, transform.columns.1.z),
            SIMD3(transform.columns.2.x, transform.columns.2.y, transform.columns.2.z)
        )
        rotation = deltaRotation * rotation

        return simd_float4x4(
            SIMD4(rotation.columns.0, 0),
            SIMD4(rotation.columns.1, 0),
            SIMD4(rotation.columns.2, 0),
            transform.columns.3
        )
    }
}

#endif
