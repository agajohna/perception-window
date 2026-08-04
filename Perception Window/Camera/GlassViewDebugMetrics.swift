//
//  GlassViewDebugMetrics.swift
//  Perception Window
//
//  Debug metrics for Glass View sensor fusion — hidden behind a flag.
//

import Foundation

#if os(iOS)

struct GlassViewDebugMetrics: Sendable {
    var viewerPoseConfidence: Float = 0
    var estimatedEyeDistanceMeters: Float = 0
    var estimatedSceneDepthMeters: Float = 0
    var sceneDepthSource: String = "fixed"
    var activeRearCameraSources: String = "none"
    var reprojectionErrorEstimate: Float = 0
    var fallbackMode: String = "passthrough"
    var thermalState: String = "nominal"
    var renderLatencyMs: Double = 0
    var frameIndex: UInt64 = 0
    var deviceTrackingState: String = "unknown"
    var imuPredictionApplied: Bool = false
    var viewerTrackerStatus: String = "stopped"
    var viewerFramesReceived: UInt64 = 0
    var viewerFacesDetected: UInt64 = 0
    var viewerLastFrameMs: Double = -1
    var eyeSource: String = "fixed"
    var warpActive: Bool = false
    var warpBlockReason: String = "initial"
    var warpExaggerationGain: Float = 1
    var maxUVShiftPixels: Float = 0
    var reprojectionHits: Int = 0
    var reprojectionGridPoints: Int = 0
    var warpPreviewEnabled: Bool = true
    var renderMode: String = "none"
    var cameraDeltaMeters: Float = 0
    var windowMagnification: Float = 1
    var lastDrawFailure: String = "starting"

    static let empty = GlassViewDebugMetrics()

    var summary: String {
        let frameAge = viewerLastFrameMs >= 0
            ? String(format: "%.0f ms ago", viewerLastFrameMs)
            : "never"
        return """
        Glass View Debug
        fallback: \(fallbackMode)
        warp: \(warpActive ? "on" : "off") (\(warpBlockReason))
        warp gain: \(String(format: "%.1f", warpExaggerationGain))×
        uv shift: \(String(format: "%.1f", maxUVShiftPixels)) px
        reproj hits: \(reprojectionHits)/\(reprojectionGridPoints)
        preview: \(warpPreviewEnabled ? "warp" : "RAW")
        render: \(renderMode)
        draw: \(lastDrawFailure)
        cam delta: \(String(format: "%.0f", cameraDeltaMeters * 1000)) mm
        front camera: \(PerceptionConfiguration.glassViewViewerPoseEnabled ? "enabled" : "disabled")
        eye source: \(eyeSource)
        viewer: \(String(format: "%.2f", viewerPoseConfidence)) [\(viewerTrackerStatus)]
        front frames/faces: \(viewerFramesReceived)/\(viewerFacesDetected)
        front last frame: \(frameAge)
        eye distance: \(String(format: "%.3f", estimatedEyeDistanceMeters)) m
        window scale: \(String(format: "%.2f", windowMagnification))×
        scene depth: \(String(format: "%.3f", estimatedSceneDepthMeters)) m (\(sceneDepthSource))
        rear sources: \(activeRearCameraSources)
        reproj error: \(String(format: "%.3f", reprojectionErrorEstimate))
        tracking: \(deviceTrackingState)
        frame: \(frameIndex)
        """
    }
}

@MainActor
final class GlassViewDebugRecorder {
    private(set) var latest = GlassViewDebugMetrics.empty

    func record(_ metrics: GlassViewDebugMetrics) {
        guard PerceptionConfiguration.glassViewDebugMetricsEnabled else { return }
        latest = metrics
    }
}

#endif
