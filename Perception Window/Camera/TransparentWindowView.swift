//
//  TransparentWindowView.swift
//  Perception Window
//

import ARKit
import MetalKit
import SceneKit
import SwiftUI

#if os(iOS)

struct TransparentWindowView: UIViewRepresentable {
    let session: TransparentWindowSession

    func makeCoordinator() -> Coordinator {
        Coordinator(session: session)
    }

    func makeUIView(context: Context) -> UIView {
        context.coordinator.makeContainerView()
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        context.coordinator.updateReference(session.sceneReference)
    }

    final class Coordinator: NSObject, MTKViewDelegate {
        private let session: TransparentWindowSession
        private let renderer: TransparentWindowRenderer?
        private var containerView = UIView()
        private var metalView: MTKView?
        private var fallbackView: ARSCNView?
        private var usesMetalFallback = false

        init(session: TransparentWindowSession) {
            self.session = session
            self.renderer = TransparentWindowRenderer()
            self.usesMetalFallback = renderer == nil
            super.init()
        }

        func makeContainerView() -> UIView {
            containerView.backgroundColor = .black

            if let renderer {
                let mtkView = MTKView()
                mtkView.device = MTLCreateSystemDefaultDevice()
                mtkView.framebufferOnly = false
                mtkView.colorPixelFormat = .bgra8Unorm
                mtkView.clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 1)
                mtkView.preferredFramesPerSecond = 30
                mtkView.isPaused = false
                mtkView.enableSetNeedsDisplay = false
                mtkView.delegate = self
                mtkView.backgroundColor = .black
                mtkView.translatesAutoresizingMaskIntoConstraints = false

                containerView.addSubview(mtkView)
                NSLayoutConstraint.activate([
                    mtkView.leadingAnchor.constraint(equalTo: containerView.leadingAnchor),
                    mtkView.trailingAnchor.constraint(equalTo: containerView.trailingAnchor),
                    mtkView.topAnchor.constraint(equalTo: containerView.topAnchor),
                    mtkView.bottomAnchor.constraint(equalTo: containerView.bottomAnchor),
                ])

                metalView = mtkView
            } else {
                attachFallbackView()
            }

            updateReference(session.sceneReference)
            return containerView
        }

        func updateReference(_ reference: VirtualEyeGeometry.SceneReference?) {
            renderer?.setSceneReference(reference)
        }

        func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {}

        func draw(in view: MTKView) {
            guard let frame = session.arSession.currentFrame else {
                switchToFallbackIfNeeded(reason: "no ARFrame")
                return
            }

            let viewportSize = CGSize(width: view.drawableSize.width, height: view.drawableSize.height)
            guard viewportSize.width > 0, viewportSize.height > 0 else { return }

            guard let copied = PixelBufferCopier.copy(frame.capturedImage) else {
                switchToFallbackIfNeeded(reason: "pixel copy failed")
                return
            }

            let snapshot = ARFrameSnapshot.make(from: frame, viewportSize: viewportSize)
            let context = TransparentWindowDrawContext(
                pixelBuffer: copied,
                snapshot: snapshot,
                warpEnabled: session.warpPreviewEnabled && session.sceneReference != nil,
                sceneReference: session.sceneReference,
                lockedCameraPosition: session.lockedCameraWorldPosition,
                lockedViewerLateral: session.lockedViewerLateral,
                warpLockBaselineDeltas: session.warpLockBaselineDeltas,
                perceptionState: session.currentPerceptionState(),
                liveViewerPose: session.liveViewerPose()
            )

            guard let renderer else {
                switchToFallbackIfNeeded(reason: "no renderer")
                return
            }

            renderer.draw(context: context, in: view)
        }

        private func attachFallbackView() {
            guard fallbackView == nil else { return }

            let arView = ARSCNView()
            arView.session = session.arSession
            arView.automaticallyUpdatesLighting = false
            arView.rendersCameraGrain = false
            arView.scene = SCNScene()
            arView.backgroundColor = .black
            arView.translatesAutoresizingMaskIntoConstraints = false

            containerView.addSubview(arView)
            NSLayoutConstraint.activate([
                arView.leadingAnchor.constraint(equalTo: containerView.leadingAnchor),
                arView.trailingAnchor.constraint(equalTo: containerView.trailingAnchor),
                arView.topAnchor.constraint(equalTo: containerView.topAnchor),
                arView.bottomAnchor.constraint(equalTo: containerView.bottomAnchor),
            ])

            fallbackView = arView
            metalView?.isPaused = true
            metalView?.isHidden = true
        }

        private func switchToFallbackIfNeeded(reason: String) {
            guard !usesMetalFallback else { return }
            usesMetalFallback = true
            attachFallbackView()
        }
    }
}

#else

struct TransparentWindowView: View {
    let session: TransparentWindowSession

    var body: some View {
        Color.black
    }
}

#endif
