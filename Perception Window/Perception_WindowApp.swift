//
//  Perception_WindowApp.swift
//  Perception Window
//

import SwiftUI

@main
struct Perception_WindowApp: App {
    @State private var camera = CameraService()
    @State private var transparentWindow = TransparentWindowSession()

    var body: some Scene {
        WindowGroup {
            ContentView(camera: camera, transparentWindow: transparentWindow)
                .task(priority: .userInitiated) {
                    if PerceptionConfiguration.usesARKitSession {
                        await transparentWindow.prepare()
                    } else {
                        await camera.prepare()
                    }
                }
        }
    }
}
