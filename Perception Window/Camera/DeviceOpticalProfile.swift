//
//  DeviceOpticalProfile.swift
//  Perception Window
//
//  Per-device display and rear-camera geometry for Stage A1 calibration.
//

import Darwin
import simd

#if os(iOS)

struct DeviceOpticalProfile {
    let modelIdentifier: String
    let marketingName: String

    /// Physical display size in portrait (meters).
    let displayWidthMeters: Float
    let displayHeightMeters: Float

    /// Rear lens optical center relative to display center, in camera coordinates (meters).
    /// Camera looks down −Z; display center sits toward +Z (user side).
    let cameraOpticalOffsetFromDisplayCenter: SIMD3<Float>

    /// Distance from rear lens plane to display plane (meters).
    let cameraToDisplayDepthMeters: Float

    /// Offset from camera origin to display center in camera coordinates.
    var screenCenterOffsetFromCameraMeters: SIMD3<Float> {
        SIMD3(
            -cameraOpticalOffsetFromDisplayCenter.x,
            -cameraOpticalOffsetFromDisplayCenter.y,
            cameraToDisplayDepthMeters - cameraOpticalOffsetFromDisplayCenter.z
        )
    }

    func virtualEyeOffsetFromCamera(eyeDistanceMeters: Float) -> SIMD3<Float> {
        screenCenterOffsetFromCameraMeters + SIMD3(0, 0, eyeDistanceMeters)
    }

    static var current: DeviceOpticalProfile {
        profile(for: machineIdentifier)
    }

    static func profile(for identifier: String) -> DeviceOpticalProfile {
        switch identifier {
        // iPhone 16 Pro / Pro Max
        case "iPhone17,1", "iPhone17,2":
            return DeviceOpticalProfile(
                modelIdentifier: identifier,
                marketingName: "iPhone 16 Pro",
                displayWidthMeters: 0.0718,
                displayHeightMeters: 0.1557,
                cameraOpticalOffsetFromDisplayCenter: SIMD3(0.000, 0.0115, 0.000),
                cameraToDisplayDepthMeters: 0.0078
            )

        // iPhone 16 / 16 Plus
        case "iPhone17,3", "iPhone17,4":
            return DeviceOpticalProfile(
                modelIdentifier: identifier,
                marketingName: "iPhone 16",
                displayWidthMeters: 0.0710,
                displayHeightMeters: 0.1540,
                cameraOpticalOffsetFromDisplayCenter: SIMD3(0.000, 0.0105, 0.000),
                cameraToDisplayDepthMeters: 0.0076
            )

        // iPhone 15 Pro / Pro Max
        case "iPhone16,1", "iPhone16,2":
            return DeviceOpticalProfile(
                modelIdentifier: identifier,
                marketingName: "iPhone 15 Pro",
                displayWidthMeters: 0.0715,
                displayHeightMeters: 0.1551,
                cameraOpticalOffsetFromDisplayCenter: SIMD3(0.000, 0.0110, 0.000),
                cameraToDisplayDepthMeters: 0.0077
            )

        // iPhone 15 / 15 Plus
        case "iPhone15,4", "iPhone15,5":
            return DeviceOpticalProfile(
                modelIdentifier: identifier,
                marketingName: "iPhone 15",
                displayWidthMeters: 0.0710,
                displayHeightMeters: 0.1538,
                cameraOpticalOffsetFromDisplayCenter: SIMD3(0.000, 0.0100, 0.000),
                cameraToDisplayDepthMeters: 0.0075
            )

        // iPhone 12 mini — baseline Glass View device
        case "iPhone13,1":
            return DeviceOpticalProfile(
                modelIdentifier: identifier,
                marketingName: "iPhone 12 mini",
                displayWidthMeters: 0.0640,
                displayHeightMeters: 0.1351,
                cameraOpticalOffsetFromDisplayCenter: SIMD3(0.000, 0.0095, 0.000),
                cameraToDisplayDepthMeters: 0.0072
            )

        // iPhone 12 / 12 Pro
        case "iPhone13,2", "iPhone13,3":
            return DeviceOpticalProfile(
                modelIdentifier: identifier,
                marketingName: "iPhone 12",
                displayWidthMeters: 0.0714,
                displayHeightMeters: 0.1467,
                cameraOpticalOffsetFromDisplayCenter: SIMD3(0.000, 0.0100, 0.000),
                cameraToDisplayDepthMeters: 0.0074
            )

        // iPhone 12 Pro Max
        case "iPhone13,4":
            return DeviceOpticalProfile(
                modelIdentifier: identifier,
                marketingName: "iPhone 12 Pro Max",
                displayWidthMeters: 0.0781,
                displayHeightMeters: 0.1609,
                cameraOpticalOffsetFromDisplayCenter: SIMD3(0.000, 0.0105, 0.000),
                cameraToDisplayDepthMeters: 0.0075
            )

        // iPhone 14 Pro / Pro Max
        case "iPhone15,2", "iPhone15,3":
            return DeviceOpticalProfile(
                modelIdentifier: identifier,
                marketingName: "iPhone 14 Pro",
                displayWidthMeters: 0.0715,
                displayHeightMeters: 0.1551,
                cameraOpticalOffsetFromDisplayCenter: SIMD3(0.000, 0.0110, 0.000),
                cameraToDisplayDepthMeters: 0.0077
            )

        default:
            return .generic(fallbackIdentifier: identifier)
        }
    }

    private static func generic(fallbackIdentifier: String) -> DeviceOpticalProfile {
        DeviceOpticalProfile(
            modelIdentifier: fallbackIdentifier,
            marketingName: "Generic iPhone",
            displayWidthMeters: 0.0710,
            displayHeightMeters: 0.1550,
            cameraOpticalOffsetFromDisplayCenter: SIMD3(0.000, 0.0110, 0.000),
            cameraToDisplayDepthMeters: 0.0076
        )
    }

    private static var machineIdentifier: String {
        var size = 0
        sysctlbyname("hw.machine", nil, &size, nil, 0)
        var machine = [CChar](repeating: 0, count: size)
        sysctlbyname("hw.machine", &machine, &size, nil, 0)
        return String(cString: machine)
    }
}

#endif
