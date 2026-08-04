//
//  PerceptionOverlayView.swift
//  Perception Window
//

import SwiftUI

struct PerceptionOverlayView: View {
    let observation: PerceptionObservation?
    let opacity: Double

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                if let observation {
                    AnchorObservationView(
                        observation: observation,
                        containerSize: geometry.size,
                        opacity: opacity
                    )
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .allowsHitTesting(opacity > 0.1)
    }
}
