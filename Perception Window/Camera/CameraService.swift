//
//  CameraService.swift
//  Perception Window
//

import AVFoundation
import Observation

#if os(iOS)

@Observable
final class CameraService: NSObject {
    enum AuthorizationState {
        case unknown
        case authorized
        case denied
    }

    nonisolated(unsafe) let session = AVCaptureSession()
    private(set) var authorizationState: AuthorizationState = .unknown
    private(set) var isRunning = false

    nonisolated(unsafe) private let sessionQueue = DispatchQueue(label: "home.perception-window.camera")
    nonisolated(unsafe) private var isConfigured = false
    nonisolated(unsafe) private var captureDevice: AVCaptureDevice?
    nonisolated(unsafe) var onFrame: (@Sendable (CMSampleBuffer) -> Void)?

    override init() {
        super.init()
        sessionQueue.async { [self] in
            configureIfNeeded()
        }
    }

    func prepare() async {
        let granted = await requestAccess()
        authorizationState = granted ? .authorized : .denied
        guard granted else { return }

        await withCheckedContinuation { continuation in
            sessionQueue.async { [self] in
                configureIfNeeded()
                continuation.resume()
            }
        }

        start()
    }

    nonisolated func start() {
        sessionQueue.async { [self] in
            configureIfNeeded()
            applyPerceptualBaselineZoomIfNeeded()
            guard !session.isRunning else { return }
            session.startRunning()
            Task { @MainActor in
                isRunning = true
            }
        }
    }

    nonisolated func stop() {
        sessionQueue.async { [self] in
            guard session.isRunning else { return }
            session.stopRunning()
            Task { @MainActor in
                isRunning = false
            }
        }
    }

    private func requestAccess() async -> Bool {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            return true
        case .notDetermined:
            return await AVCaptureDevice.requestAccess(for: .video)
        default:
            return false
        }
    }

    nonisolated private func configureIfNeeded() {
        guard !isConfigured else { return }
        session.beginConfiguration()
        defer { session.commitConfiguration() }

        session.sessionPreset = .high

        guard
            let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back),
            let input = try? AVCaptureDeviceInput(device: device),
            session.canAddInput(input)
        else {
            return
        }

        session.addInput(input)
        captureDevice = device

        let output = AVCaptureVideoDataOutput()
        output.videoSettings = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
        ]
        output.alwaysDiscardsLateVideoFrames = true
        output.setSampleBufferDelegate(self, queue: sessionQueue)

        guard session.canAddOutput(output) else { return }
        session.addOutput(output)
        isConfigured = true
    }

    /// Physical zoom applied after session configuration — Curiosity perceptual 1.0× window state.
    nonisolated private func applyPerceptualBaselineZoomIfNeeded() {
        guard let device = captureDevice else { return }
        let target = PerceptionConfiguration.perceptualBaselineZoom
        guard target > 1.0 else { return }

        do {
            try device.lockForConfiguration()
            defer { device.unlockForConfiguration() }
            let clamped = min(
                max(target, device.minAvailableVideoZoomFactor),
                device.activeFormat.videoMaxZoomFactor
            )
            device.videoZoomFactor = clamped
        } catch {
            // Baseline zoom is best-effort — preview still works at 1.0×.
        }
    }
}

extension CameraService: AVCaptureVideoDataOutputSampleBufferDelegate {
    nonisolated func captureOutput(
        _ output: AVCaptureOutput,
        didOutput sampleBuffer: CMSampleBuffer,
        from connection: AVCaptureConnection
    ) {
        onFrame?(sampleBuffer)
    }
}

#else

@Observable
final class CameraService {
    enum AuthorizationState {
        case unknown
        case authorized
        case denied
    }

    let session = AVCaptureSession()
    private(set) var authorizationState: AuthorizationState = .denied
    private(set) var isRunning = false

    var onFrame: (@Sendable (CMSampleBuffer) -> Void)?

    func prepare() async {}
    func start() {}
    func stop() {}
}

#endif
