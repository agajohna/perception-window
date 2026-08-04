//
//  GlassViewDebugOverlay.swift
//  Perception Window
//

import SwiftUI

#if os(iOS)

struct GlassViewDebugOverlay: View {
    let session: TransparentWindowSession

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            TimelineView(.periodic(from: .now, by: 0.25)) { _ in
                VStack(alignment: .leading, spacing: 4) {
                    Text("Glass View")
                        .font(.caption.bold())
                    Text(session.debugMetrics.summary)
                        .font(.caption2.monospaced())
                        .multilineTextAlignment(.leading)
                }
            }

            Button {
                session.toggleWarpPreview()
            } label: {
                Text(session.debugMetrics.warpPreviewEnabled ? "Switch to RAW" : "Switch to WARP")
                    .font(.caption2.bold())
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(.white.opacity(0.2))
                    .clipShape(RoundedRectangle(cornerRadius: 4))
            }
            .buttonStyle(.plain)
            .padding(.top, 6)
        }
        .padding(10)
        .background(.black.opacity(0.55))
        .foregroundStyle(.white.opacity(0.9))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(.top, 52)
        .padding(.leading, 12)
    }
}

#endif
