//
//  ViewerPoseTracker.swift
//  Perception Window
//
//  Coarse viewer/eye pose from front camera — on-device only, active while Glass View runs.
//

import AVFoundation
import CoreMedia
import simd
import Vision

#if os(iOS)

enum ViewerTrackerStatus: String, Sendable {
    case stopped
    case starting
    case active
    case runningNoFrames
    case unavailable
}

final class ViewerPoseTracker: NSObject {
    private var captureSession: AVCaptureSession?
    private let videoOutput = AVCaptureVideoDataOutput()
    private let outputQueue = DispatchQueue(label: "viewer.pose.output", qos: .userInteractive)

    private let lock = NSLock()
    private var latestEstimate = ViewerPoseEstimate.invalid
    private var status: ViewerTrackerStatus = .stopped
    private var isConfigured = false
    private var isRunning = false
    private var lastProcessTime: TimeInterval = 0
    private var framesReceived: UInt64 = 0
    private var facesDetected: UInt64 = 0
    private var lastFrameTime: TimeInterval = 0
    private var usesMultiCam = false

    private lazy var faceRequest: VNDetectFaceLandmarksRequest = {
        let request = VNDetectFaceLandmarksRequest()
        request.revision = VNDetectFaceLandmarksRequestRevision3
        return request
    }()

    /// Start front camera before ARKit claims hardware when possible.
    func start() {
        guard PerceptionConfiguration.glassViewViewerPoseEnabled else { return }
        if ARKitFaceViewerTracker.isSupported {
            setStatus(.starting)
            return
        }
        guard !isRunning else { return }

        setStatus(.starting)

        outputQueue.async { [weak self] in
            guard let self else { return }
            self.activateAudioSession()
            if !self.isConfigured {
                self.configureSession()
            }
            guard let session = self.captureSession, self.isConfigured else {
                self.setStatus(.unavailable)
                return
            }
            session.startRunning()
            self.isRunning = true
            self.setStatus(.runningNoFrames)
            self.scheduleFrameWatchdog()
        }
    }

    func stop() {
        guard isRunning || status == .starting else { return }
        outputQueue.async { [weak self] in
            guard let self else { return }
            self.captureSession?.stopRunning()
            self.captureSession = nil
            self.isRunning = false
            self.isConfigured = false
            self.lock.lock()
            self.latestEstimate = .invalid
            self.framesReceived = 0
            self.facesDetected = 0
            self.lastFrameTime = 0
            self.lock.unlock()
            self.setStatus(.stopped)
        }
    }

    func currentEstimate() -> ViewerPoseEstimate {
        lock.lock()
        defer { lock.unlock() }

        guard latestEstimate.isValid else { return .invalid }

        let staleAfter = 0.35
        if lastFrameTime == 0 || CACurrentMediaTime() - lastFrameTime > staleAfter {
            return .invalid
        }

        return latestEstimate
    }

    func diagnosticSnapshot() -> (
        status: ViewerTrackerStatus,
        framesReceived: UInt64,
        facesDetected: UInt64,
        secondsSinceFrame: TimeInterval,
        usesMultiCam: Bool
    ) {
        lock.lock()
        defer { lock.unlock() }
        let since = lastFrameTime > 0 ? CACurrentMediaTime() - lastFrameTime : -1
        return (status, framesReceived, facesDetected, since, usesMultiCam)
    }

    private func setStatus(_ newStatus: ViewerTrackerStatus) {
        lock.lock()
        status = newStatus
        lock.unlock()
    }

    private func activateAudioSession() {
        let audioSession = AVAudioSession.sharedInstance()
        try? audioSession.setCategory(.playAndRecord, mode: .videoChat, options: [.defaultToSpeaker, .mixWithOthers])
        try? audioSession.setActive(true, options: [])
    }

    private func configureSession() {
        captureSession = nil
        isConfigured = false
        usesMultiCam = false

        if AVCaptureMultiCamSession.isMultiCamSupported, configureMultiCam() {
            return
        }
        configureSingleCam()
    }

    private func configureMultiCam() -> Bool {
        let session = AVCaptureMultiCamSession()
        session.beginConfiguration()

        guard let device = preferredFrontDevice() else {
            session.commitConfiguration()
            return false
        }

        guard let input = try? AVCaptureDeviceInput(device: device), session.canAddInput(input) else {
            session.commitConfiguration()
            return false
        }
        session.addInputWithNoConnections(input)

        guard let port = input.ports.first(where: { $0.mediaType == .video }) else {
            session.commitConfiguration()
            return false
        }

        videoOutput.alwaysDiscardsLateVideoFrames = true
        videoOutput.videoSettings = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
        ]

        guard session.canAddOutput(videoOutput) else {
            session.commitConfiguration()
            return false
        }
        session.addOutputWithNoConnections(videoOutput)

        let connection = AVCaptureConnection(inputPorts: [port], output: videoOutput)
        guard session.canAddConnection(connection) else {
            session.commitConfiguration()
            return false
        }
        session.addConnection(connection)

        if #available(iOS 17.0, *) {
            connection.videoRotationAngle = 90
        } else {
            connection.videoOrientation = .portrait
        }
        if connection.isVideoMirroringSupported {
            connection.isVideoMirrored = true
        }

        session.commitConfiguration()
        videoOutput.setSampleBufferDelegate(self, queue: outputQueue)
        captureSession = session
        usesMultiCam = true
        isConfigured = true
        return true
    }

    private func configureSingleCam() {
        let session = AVCaptureSession()
        session.automaticallyConfiguresApplicationAudioSession = false
        session.beginConfiguration()

        if session.canSetSessionPreset(.vga640x480) {
            session.sessionPreset = .vga640x480
        } else {
            session.sessionPreset = .medium
        }

        guard let device = preferredFrontDevice(),
              let input = try? AVCaptureDeviceInput(device: device),
              session.canAddInput(input) else {
            session.commitConfiguration()
            return
        }

        session.addInput(input)

        videoOutput.alwaysDiscardsLateVideoFrames = true
        videoOutput.videoSettings = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
        ]

        guard session.canAddOutput(videoOutput) else {
            session.commitConfiguration()
            return
        }

        session.addOutput(videoOutput)
        videoOutput.setSampleBufferDelegate(self, queue: outputQueue)

        if let connection = videoOutput.connection(with: .video) {
            if #available(iOS 17.0, *) {
                connection.videoRotationAngle = 90
            } else {
                connection.videoOrientation = .portrait
            }
            if connection.isVideoMirroringSupported {
                connection.isVideoMirrored = true
            }
        }

        session.commitConfiguration()
        captureSession = session
        usesMultiCam = false
        isConfigured = true
    }

    private func scheduleFrameWatchdog() {
        outputQueue.asyncAfter(deadline: .now() + 3.0) { [weak self] in
            guard let self, self.isRunning else { return }
            self.lock.lock()
            let received = self.framesReceived
            self.lock.unlock()
            guard received == 0 else { return }

            // Front camera cannot run alongside ARKit on this device — release it
            // so rear tracking stays stable.
            self.captureSession?.stopRunning()
            self.captureSession = nil
            self.isRunning = false
            self.isConfigured = false
            self.setStatus(.unavailable)
        }
    }

    private func preferredFrontDevice() -> AVCaptureDevice? {
        let discovery = AVCaptureDevice.DiscoverySession(
            deviceTypes: [.builtInTrueDepthCamera, .builtInWideAngleCamera],
            mediaType: .video,
            position: .front
        )
        return discovery.devices.first
    }

    private func publishEstimate(_ estimate: ViewerPoseEstimate) {
        lock.lock()
        latestEstimate = estimate
        if estimate.isValid {
            facesDetected &+= 1
            status = .active
        } else if framesReceived > 0 {
            status = .runningNoFrames
        }
        lock.unlock()
    }

    private func processVideoSample(_ sampleBuffer: CMSampleBuffer) {
        let now = CACurrentMediaTime()

        lock.lock()
        framesReceived &+= 1
        lastFrameTime = now
        lock.unlock()

        let minInterval = 1.0 / PerceptionConfiguration.viewerPoseUpdateRateHz
        guard now - lastProcessTime >= minInterval else { return }
        lastProcessTime = now

        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else {
            publishEstimate(.invalid)
            return
        }

        let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, orientation: .leftMirrored, options: [:])
        do {
            try handler.perform([faceRequest])
        } catch {
            publishEstimate(.invalid)
            return
        }

        guard
            let observation = faceRequest.results?.first as? VNFaceObservation,
            observation.confidence > 0.35
        else {
            publishEstimate(.invalid)
            return
        }

        let profile = DeviceOpticalProfile.current
        let eyeDistance = estimateEyeDistance(from: observation)
        let lateral = estimateLateralOffset(from: observation, profile: profile)
        let gain = PerceptionConfiguration.viewerPoseLateralGain

        let eyeLocal = profile.virtualEyeOffsetFromCamera(eyeDistanceMeters: eyeDistance)
            + SIMD3(lateral.x * gain, lateral.y * gain, 0)

        publishEstimate(
            ViewerPoseEstimate(
                eyeMidpointDevice: eyeLocal,
                eyeToScreenDistanceMeters: eyeDistance,
                lateralOffsetMeters: lateral,
                confidence: Float(observation.confidence),
                isValid: true,
                timestamp: now
            )
        )
    }

    private func estimateEyeDistance(from face: VNFaceObservation) -> Float {
        let fallback = PerceptionConfiguration.virtualEyeDistanceMeters
        guard let landmarks = face.landmarks else { return fallback }

        if let leftEye = landmarks.leftEye, let rightEye = landmarks.rightEye {
            let leftCenter = centroid(of: leftEye)
            let rightCenter = centroid(of: rightEye)
            let interocular = hypot(leftCenter.x - rightCenter.x, leftCenter.y - rightCenter.y)
            guard interocular > 0.01 else { return fallback }

            let normalized = Float(interocular / face.boundingBox.width)
            let estimated = 0.065 / max(normalized, 0.08)
            return min(max(estimated, 0.30), 0.65)
        }

        let faceHeight = Float(face.boundingBox.height)
        guard faceHeight > 0.05 else { return fallback }
        let estimated = 0.12 / faceHeight
        return min(max(estimated, 0.30), 0.65)
    }

    private func estimateLateralOffset(from face: VNFaceObservation, profile: DeviceOpticalProfile) -> SIMD2<Float> {
        let imageMidpoint: CGPoint
        if
            let landmarks = face.landmarks,
            let leftEye = landmarks.leftEye,
            let rightEye = landmarks.rightEye
        {
            let left = landmarkInImage(centroid(of: leftEye), face: face)
            let right = landmarkInImage(centroid(of: rightEye), face: face)
            imageMidpoint = CGPoint(x: (left.x + right.x) * 0.5, y: (left.y + right.y) * 0.5)
        } else {
            imageMidpoint = CGPoint(x: face.boundingBox.midX, y: face.boundingBox.midY)
        }

        return SIMD2(
            Float(imageMidpoint.x - 0.5) * profile.displayWidthMeters,
            Float(imageMidpoint.y - 0.5) * profile.displayHeightMeters
        )
    }

    private func landmarkInImage(_ point: CGPoint, face: VNFaceObservation) -> CGPoint {
        let box = face.boundingBox
        return CGPoint(
            x: box.origin.x + point.x * box.width,
            y: box.origin.y + point.y * box.height
        )
    }

    private func centroid(of region: VNFaceLandmarkRegion2D) -> CGPoint {
        let points = region.normalizedPoints
        guard !points.isEmpty else { return .zero }
        var sum = CGPoint.zero
        for point in points {
            sum.x += CGFloat(point.x)
            sum.y += CGFloat(point.y)
        }
        return CGPoint(x: sum.x / CGFloat(points.count), y: sum.y / CGFloat(points.count))
    }
}

extension ViewerPoseTracker: AVCaptureVideoDataOutputSampleBufferDelegate {
    func captureOutput(
        _ output: AVCaptureOutput,
        didOutput sampleBuffer: CMSampleBuffer,
        from connection: AVCaptureConnection
    ) {
        processVideoSample(sampleBuffer)
    }
}

#endif
