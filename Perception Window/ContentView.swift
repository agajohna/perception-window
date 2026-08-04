//
//  ContentView.swift
//  Perception Window
//

import SwiftUI

struct ContentView: View {
    @Bindable var camera: CameraService
    @State private var perception = PerceptionViewModel()

    var body: some View {
        ZStack {
            #if os(iOS)
            if camera.authorizationState == .authorized {
                CameraPreviewView(session: camera.session)
                    .ignoresSafeArea()
            } else {
                Color.black
                    .ignoresSafeArea()
            }
            #else
            Color.black
                .ignoresSafeArea()
            #endif

            PerceptionOverlayView(
                observation: perception.displayedObservation,
                opacity: perception.observationOpacity
            )
            .ignoresSafeArea()

            if camera.authorizationState == .denied {
                Text("Camera access is required")
                    .font(.footnote)
                    .foregroundStyle(.white.opacity(0.5))
            }

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
            perception.attach(to: camera)
        }
        .onDisappear {
            camera.stop()
        }
    }
}

#Preview {
    ContentView(camera: CameraService())
}
