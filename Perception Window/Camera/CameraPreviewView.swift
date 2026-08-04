//
//  CameraPreviewView.swift
//  Perception Window
//

import AVFoundation
import SwiftUI

#if os(iOS)

struct CameraPreviewView: UIViewRepresentable {
    let session: AVCaptureSession
    var isLensActive: Bool
    var lensAnchor: CGPoint
    var lensMagnification: CGFloat

    init(
        session: AVCaptureSession,
        isLensActive: Bool = false,
        lensAnchor: CGPoint = CGPoint(x: 0.5, y: 0.5),
        lensMagnification: CGFloat = PerceptionConfiguration.lensMagnification
    ) {
        self.session = session
        self.isLensActive = isLensActive
        self.lensAnchor = lensAnchor
        self.lensMagnification = lensMagnification
    }

    func makeUIView(context: Context) -> CameraPreviewUIView {
        let view = CameraPreviewUIView()
        view.attachSession(session)
        return view
    }

    func updateUIView(_ uiView: CameraPreviewUIView, context: Context) {
        uiView.attachSession(session)
        uiView.updateLens(
            isActive: isLensActive,
            anchor: lensAnchor,
            magnification: lensMagnification
        )
    }
}

final class CameraPreviewUIView: UIView {
    /// Root layer is the preview layer — required for reliable AVFoundation connection.
    override class var layerClass: AnyClass {
        AVCaptureVideoPreviewLayer.self
    }

    var previewLayer: AVCaptureVideoPreviewLayer {
        layer as! AVCaptureVideoPreviewLayer
    }

    let lensLayer = AVCaptureVideoPreviewLayer()

    private let lensWrapper = CALayer()
    private let lensMask = CAShapeLayer()
    private var lensIsActive = false
    private var storedAnchor = CGPoint(x: 0.5, y: 0.5)
    private var storedMagnification = PerceptionConfiguration.lensMagnification
    private var lastAppliedActive = false

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .black

        previewLayer.videoGravity = .resizeAspectFill

        lensLayer.videoGravity = .resizeAspectFill
        lensWrapper.addSublayer(lensLayer)
        lensWrapper.mask = lensMask
        lensWrapper.isHidden = true
        layer.addSublayer(lensWrapper)

        lensMask.fillColor = UIColor.white.cgColor
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func attachSession(_ session: AVCaptureSession) {
        guard previewLayer.session !== session else {
            if lensLayer.session !== session {
                lensLayer.session = session
            }
            return
        }
        previewLayer.session = session
        lensLayer.session = session
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        lensWrapper.frame = bounds
        lensLayer.frame = bounds
        refreshLensMask()
        if lensIsActive {
            applyLensTransform(animated: false)
        }
    }

    func updateLens(isActive: Bool, anchor: CGPoint, magnification: CGFloat) {
        let shouldAnimate = lastAppliedActive != isActive
        lensIsActive = isActive
        storedAnchor = anchor
        storedMagnification = magnification
        lastAppliedActive = isActive

        if isActive {
            lensWrapper.isHidden = false
            refreshLensMask()
            applyLensTransform(animated: shouldAnimate)
        } else if shouldAnimate {
            CATransaction.begin()
            CATransaction.setAnimationDuration(PerceptionConfiguration.lensAnimationDuration)
            CATransaction.setAnimationTimingFunction(CAMediaTimingFunction(name: .easeInEaseOut))
            lensLayer.setAffineTransform(.identity)
            CATransaction.commit()

            DispatchQueue.main.asyncAfter(deadline: .now() + PerceptionConfiguration.lensAnimationDuration) { [weak self] in
                guard self?.lensIsActive == false else { return }
                self?.lensWrapper.isHidden = true
            }
        } else {
            lensLayer.setAffineTransform(.identity)
            lensWrapper.isHidden = true
        }
    }

    private func lensMaskPosition(for anchor: CGPoint) -> CGPoint {
        CGPoint(x: anchor.x * bounds.width, y: anchor.y * bounds.height)
    }

    private func refreshLensMask() {
        guard bounds.width > 0, bounds.height > 0 else { return }
        let center = lensMaskPosition(for: storedAnchor)
        let radius = PerceptionConfiguration.lensRegionRadius
        lensMask.path = UIBezierPath(
            arcCenter: center,
            radius: radius,
            startAngle: 0,
            endAngle: .pi * 2,
            clockwise: true
        ).cgPath
    }

    private func applyLensTransform(animated: Bool) {
        guard bounds.width > 0, bounds.height > 0 else { return }

        let center = lensMaskPosition(for: storedAnchor)
        var transform = CGAffineTransform.identity
        transform = transform.translatedBy(x: center.x, y: center.y)
        transform = transform.scaledBy(x: storedMagnification, y: storedMagnification)
        transform = transform.translatedBy(x: -center.x, y: -center.y)

        if animated {
            CATransaction.begin()
            CATransaction.setAnimationDuration(PerceptionConfiguration.lensAnimationDuration)
            CATransaction.setAnimationTimingFunction(CAMediaTimingFunction(name: .easeInEaseOut))
            lensLayer.setAffineTransform(transform)
            CATransaction.commit()
        } else {
            lensLayer.setAffineTransform(transform)
        }
    }
}

#else

struct CameraPreviewView: View {
    let session: AVCaptureSession
    var isLensActive: Bool = false
    var lensAnchor: CGPoint = CGPoint(x: 0.5, y: 0.5)
    var lensMagnification: CGFloat = 1.0

    var body: some View {
        Color.black
    }
}

#endif
