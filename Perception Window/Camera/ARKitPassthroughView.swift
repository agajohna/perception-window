//
//  ARKitPassthroughView.swift
//  Perception Window
//
//  Step 2 — native ARKit live camera via ARSCNView (no custom Metal warp).
//

import ARKit
import SceneKit
import SwiftUI

#if os(iOS)

struct ARKitPassthroughView: UIViewRepresentable {
    let session: TransparentWindowSession

    func makeUIView(context: Context) -> ARSCNView {
        let view = ARSCNView(frame: .zero)
        view.session = session.arSession
        view.automaticallyUpdatesLighting = false
        view.rendersCameraGrain = false
        view.scene = SCNScene()
        view.backgroundColor = .black
        return view
    }

    func updateUIView(_ uiView: ARSCNView, context: Context) {
        if uiView.session !== session.arSession {
            uiView.session = session.arSession
        }
    }
}

#else

struct ARKitPassthroughView: View {
    let session: TransparentWindowSession

    var body: some View {
        Color.black
    }
}

#endif
