//
//  AnchorObservationView.swift
//  Perception Window
//

import SwiftUI

struct AnchorObservationView: View {
    let observation: PerceptionObservation
    let containerSize: CGSize
    let opacity: Double

    @State private var isExpanded = false

    private let dotSize: CGFloat = 5

    var body: some View {
        let anchor = CGPoint(
            x: observation.anchor.x * containerSize.width,
            y: observation.anchor.y * containerSize.height
        )

        VStack(spacing: 6) {
            Circle()
                .fill(.white.opacity(0.9))
                .frame(width: dotSize, height: dotSize)

            labelContent
        }
        .position(clampedPosition(for: anchor))
        .opacity(opacity)
        .animation(.easeOut(duration: 0.35), value: observation.anchor.x)
        .animation(.easeOut(duration: 0.35), value: observation.anchor.y)
        .animation(.easeOut(duration: 0.35), value: opacity)
        .onChange(of: observation.primary) { _, _ in
            isExpanded = false
        }
    }

    @ViewBuilder
    private var labelContent: some View {
        if isExpanded, let detail = observation.detail {
            VStack(alignment: .leading, spacing: 8) {
                Text(observation.primary)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.white.opacity(0.95))

                Rectangle()
                    .fill(.white.opacity(0.25))
                    .frame(height: 0.5)

                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.78))
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(.black.opacity(0.35), in: RoundedRectangle(cornerRadius: 10))
        } else {
            Text(observation.primary)
                .font(.subheadline.weight(.regular))
                .foregroundStyle(.white.opacity(0.92))
                .multilineTextAlignment(.center)
                .onTapGesture {
                    guard observation.detail != nil else { return }
                    withAnimation(.easeOut(duration: 0.25)) {
                        isExpanded.toggle()
                    }
                }
        }
    }

    private func clampedPosition(for anchor: CGPoint) -> CGPoint {
        let labelWidth: CGFloat = isExpanded ? 220 : min(max(CGFloat(observation.primary.count) * 7.2, 80), 220)
        let labelHeight: CGFloat = isExpanded ? 120 : 20
        let stackHeight = dotSize + 6 + labelHeight

        var center = CGPoint(
            x: anchor.x + labelWidth / 2,
            y: anchor.y + stackHeight / 2
        )

        center.x = min(max(center.x, labelWidth / 2 + 16), containerSize.width - labelWidth / 2 - 16)
        center.y = min(max(center.y, stackHeight / 2 + 56), containerSize.height - stackHeight / 2 - 120)

        return center
    }
}
