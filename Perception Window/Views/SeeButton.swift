//
//  SeeButton.swift
//  Perception Window
//

import SwiftUI

#if os(iOS)
import UIKit
#endif

struct SeeButton: View {
    let isActive: Bool
    let focusProgress: Double
    let onHoldChanged: (Bool) -> Void

    @State private var isPressed = false

    private let size: CGFloat = 61
    private let dilationDuration: Double = 0.2

    var body: some View {
        ZStack {
            Circle()
                .strokeBorder(.white.opacity(isActive ? 0.22 : 0.18), lineWidth: 1.5)
                .background(
                    Circle()
                        .fill(.white.opacity(isActive ? 0.06 : 0.03))
                )
                .frame(width: size, height: size)

            Circle()
                .trim(from: 0, to: isActive ? focusProgress : 0)
                .stroke(
                    .white.opacity(0.7),
                    style: StrokeStyle(lineWidth: 2, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
                .frame(width: size - 6, height: size - 6)
                .animation(.linear(duration: 0.05), value: focusProgress)

            pupil
        }
        .contentShape(Circle())
        .gesture(holdGesture)
        .accessibilityLabel("See")
        .accessibilityAddTraits(.isButton)
    }

    private var pupil: some View {
        ZStack {
            Ellipse()
                .strokeBorder(.white.opacity(isActive ? 0.75 : 0.42), lineWidth: 1.1)
                .frame(width: 27, height: 16)

            Circle()
                .fill(.white.opacity(isActive ? 0.28 : 0.14))
                .frame(width: isActive ? 18 : 12, height: isActive ? 18 : 12)

            Circle()
                .fill(.white.opacity(isActive ? 0.92 : 0.58))
                .frame(width: isActive ? 8.5 : 5, height: isActive ? 8.5 : 5)
        }
        .animation(.easeOut(duration: dilationDuration), value: isActive)
    }

    private var holdGesture: some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { _ in
                guard !isPressed else { return }
                isPressed = true
                onHoldChanged(true)
                haptic(.light)
            }
            .onEnded { _ in
                guard isPressed else { return }
                isPressed = false
                onHoldChanged(false)
                haptic(.soft)
            }
    }

    private func haptic(_ style: HapticStyle) {
        #if os(iOS)
        switch style {
        case .light:
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        case .soft:
            UIImpactFeedbackGenerator(style: .soft).impactOccurred()
        }
        #endif
    }

    private enum HapticStyle {
        case light
        case soft
    }
}
