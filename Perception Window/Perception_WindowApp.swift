//
//  Perception_WindowApp.swift
//  Perception Window
//

import SwiftUI

@main
struct Perception_WindowApp: App {
    @State private var camera = CameraService()

    var body: some Scene {
        WindowGroup {
            ContentView(camera: camera)
                .task(priority: .userInitiated) {
                    await camera.prepare()
                }
        }
    }
}
