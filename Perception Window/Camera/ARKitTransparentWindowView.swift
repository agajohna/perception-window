//
//  ARKitTransparentWindowView.swift
//  Perception Window
//

import ARKit
import MetalKit
import SwiftUI

#if os(iOS)

struct ARKitTransparentWindowView: UIViewRepresentable {
    let session: TransparentWindowSession

    func makeCoordinator() -> Coordinator {
        Coordinator(session: session)
    }

    func makeUIView(context: Context) -> UIView {
        context.coordinator.makeContainerView()
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        context.coordinator.attachSession(session)
    }

    static func dismantleUIView(_ uiView: UIView, coordinator: Coordinator) {
        coordinator.warpView.delegate = nil
        coordinator.warpView.isPaused = true
    }

    final class Coordinator: NSObject, MTKViewDelegate {
        private var session: TransparentWindowSession?
        let renderer: TransparentWindowRenderer
        let warpView = MTKView()

        init(session: TransparentWindowSession) {
            guard let renderer = TransparentWindowRenderer() else {
                fatalError("TransparentWindowRenderer failed to initialize")
            }
            self.session = session
            self.renderer = renderer
            super.init()
        }

        func attachSession(_ session: TransparentWindowSession) {
            self.session = session
        }

        func makeContainerView() -> UIView {
            let container = UIView()
            container.backgroundColor = .black

            guard let device = MTLCreateSystemDefaultDevice() else {
                return container
            }

            warpView.device = device
            warpView.framebufferOnly = false
            warpView.colorPixelFormat = .bgra8Unorm
            warpView.clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 1)
            warpView.preferredFramesPerSecond = 60
            warpView.enableSetNeedsDisplay = false
            warpView.isPaused = false
            warpView.delegate = self
            warpView.backgroundColor = .black
            warpView.isOpaque = true
            warpView.contentScaleFactor = UIScreen.main.scale
            warpView.translatesAutoresizingMaskIntoConstraints = false

            container.addSubview(warpView)

            NSLayoutConstraint.activate([
                warpView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
                warpView.trailingAnchor.constraint(equalTo: container.trailingAnchor),
                warpView.topAnchor.constraint(equalTo: container.topAnchor),
                warpView.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            ])

            return container
        }

        func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {
            guard let session else { return }
            session.setFusionViewportSize(resolvedViewportSize(for: view, drawableSize: size))
        }

        func draw(in view: MTKView) {
            guard let session else { return }

            let viewportSize = resolvedViewportSize(for: view, drawableSize: view.drawableSize)
            guard viewportSize.width > 1, viewportSize.height > 1 else { return }

            session.setFusionViewportSize(viewportSize)

            guard let packet = session.renderFrame(for: viewportSize) else {
                session.recordDrawFailure("no frame")
                return
            }

            let sceneReference = session.effectiveSceneReference
            let useWarp = session.warpPreviewEnabled && sceneReference != nil

            let context = TransparentWindowDrawContext(
                pixelBuffer: packet.pixelBuffer,
                snapshot: packet.snapshot,
                warpEnabled: useWarp,
                sceneReference: sceneReference,
                lockedCameraPosition: session.lockedCameraWorldPosition,
                lockedViewerLateral: session.lockedViewerLateral,
                warpLockBaselineDeltas: session.warpLockBaselineDeltas,
                perceptionState: session.currentPerceptionState(),
                liveViewerPose: session.liveViewerPose()
            )

            let drawResult = renderer.draw(context: context, in: view)
            session.recordWarpDiagnostics(
                presented: drawResult.presented,
                failureReason: drawResult.failureReason,
                renderMode: drawResult.renderMode,
                maxUVShiftPixels: drawResult.maxUVShiftPixels,
                reprojectionHits: drawResult.reprojectionHits,
                gridPointCount: drawResult.gridPointCount,
                cameraDeltaMeters: drawResult.cameraDeltaMeters,
                windowMagnification: drawResult.windowMagnification,
                staticAlignPixels: drawResult.staticAlignPixels
            )
        }

        private func resolvedViewportSize(for view: MTKView, drawableSize: CGSize) -> CGSize {
            if drawableSize.width > 1, drawableSize.height > 1 {
                return drawableSize
            }
            let scale = view.contentScaleFactor
            return CGSize(
                width: max(view.bounds.width * scale, 1),
                height: max(view.bounds.height * scale, 1)
            )
        }
    }
}

#else

struct ARKitTransparentWindowView: View {
    let session: TransparentWindowSession

    var body: some View {
        Color.black
    }
}

#endif
