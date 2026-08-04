//
//  ContentView.swift
//  Perception Window
//

import SwiftUI

struct ContentView: View {
    @Bindable var camera: CameraService
    @Bindable var transparentWindow: TransparentWindowSession
    @State private var perception = PerceptionViewModel()
    @State private var perceptualWindow = PerceptualWindowStabilizer()

    var body: some View {
        ZStack {
            #if os(iOS)
            previewLayer
            #else
            Color.black
                .ignoresSafeArea()
            #endif

            PerceptionOverlayView(
                observation: perception.displayedObservation,
                opacity: perception.observationOpacity
            )
            .ignoresSafeArea()

            #if os(iOS)
            if activeAuthorizationState == .denied {
                Text("Camera access is required")
                    .font(.footnote)
                    .foregroundStyle(.white.opacity(0.5))
            }

            if PerceptionConfiguration.glassViewDebugMetricsEnabled {
                GlassViewDebugOverlay(session: transparentWindow)
            }
            #endif

            VStack {
                Spacer()

                SeeButton(
                    isActive: perception.isPerceiving,
                    focusProgress: perception.focusProgress
                ) { isHolding in
                    if isHolding {
                        perception.begin()
                    } else {
                        perception.end()
                    }
                }
                .padding(.bottom, 40)
            }
        }
        .statusBarHidden(true)
        .persistentSystemOverlays(.hidden)
        .onAppear {
            attachPerceptionSource()
            if PerceptionConfiguration.usesAVCapturePreview {
                perceptualWindow.start()
            }
        }
        .onDisappear {
            perceptualWindow.stop()
            if PerceptionConfiguration.usesARKitSession {
                transparentWindow.stop()
            } else {
                camera.stop()
            }
        }
        .onTapGesture(count: 2) {
            guard PerceptionConfiguration.usesViewpointReprojection else { return }
            transparentWindow.recenterVirtualEye()
        }
        .onTapGesture(count: 3) {
            guard PerceptionConfiguration.usesViewpointReprojection else { return }
            transparentWindow.toggleWarpPreview()
        }
    }

    #if os(iOS)
    @ViewBuilder
    private var previewLayer: some View {
        switch PerceptionConfiguration.previewMode {
        case .arKitReprojection, .arKitPassthrough:
            if transparentWindow.authorizationState == .authorized {
                ARKitTransparentWindowView(session: transparentWindow)
                    .ignoresSafeArea()
            } else if transparentWindow.authorizationState == .denied {
                Color.black.ignoresSafeArea()
            } else {
                Color.black.ignoresSafeArea()
            }

        case .avCapture:
            if camera.authorizationState == .authorized && camera.isRunning {
                CameraPreviewView(
                    session: camera.session,
                    perceptualTransform: perceptualWindow.previewTransform
                )
                .ignoresSafeArea()
            } else if camera.authorizationState == .denied {
                Color.black.ignoresSafeArea()
            } else {
                Color.black.ignoresSafeArea()
            }
        }
    }

    private var activeAuthorizationState: TransparentWindowSession.AuthorizationState {
        if PerceptionConfiguration.usesARKitSession {
            transparentWindow.authorizationState
        } else {
            switch camera.authorizationState {
            case .unknown: .unknown
            case .authorized: .authorized
            case .denied: .denied
            }
        }
    }

    private func attachPerceptionSource() {
        if PerceptionConfiguration.usesARKitSession {
            perception.attach(to: transparentWindow)
        } else {
            perception.attach(to: camera)
        }
    }
    #endif
}

#Preview {
    ContentView(camera: CameraService(), transparentWindow: TransparentWindowSession())
}
