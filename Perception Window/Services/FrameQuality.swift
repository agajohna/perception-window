//
//  FrameQuality.swift
//  Perception Window
//

import CoreGraphics
import Foundation

#if os(iOS)
import UIKit
#endif

struct FrameQualityScore: Equatable {
    let score: Float
    let isSharpEnough: Bool
    let isBrightEnough: Bool

    var isAcceptable: Bool { isSharpEnough && isBrightEnough }
}

enum FrameQuality {
    /// On-device gate — blur and exposure before any API call.
    static func assess(_ jpeg: Data) -> FrameQualityScore {
        #if os(iOS)
        guard
            let image = UIImage(data: jpeg),
            let cgImage = image.cgImage
        else {
            return FrameQualityScore(score: 0, isSharpEnough: false, isBrightEnough: false)
        }

        let width = min(cgImage.width, 320)
        let height = min(cgImage.height, 320)
        let colorSpace = CGColorSpaceCreateDeviceGray()
        var pixels = [UInt8](repeating: 0, count: width * height)

        guard
            let context = CGContext(
                data: &pixels,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: width,
                space: colorSpace,
                bitmapInfo: CGImageAlphaInfo.none.rawValue
            )
        else {
            return FrameQualityScore(score: 0, isSharpEnough: false, isBrightEnough: false)
        }

        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))

        let sharpness = laplacianVariance(pixels: pixels, width: width, height: height)
        let brightness = averageBrightness(pixels: pixels)

        let isSharpEnough = sharpness >= PerceptionConfiguration.minimumSharpness
        let isBrightEnough = brightness >= PerceptionConfiguration.minimumBrightness
            && brightness <= PerceptionConfiguration.maximumBrightness

        let score = sharpness * 0.7 + brightnessPenalty(brightness) * 0.3
        return FrameQualityScore(score: score, isSharpEnough: isSharpEnough, isBrightEnough: isBrightEnough)
        #else
        return FrameQualityScore(score: 1, isSharpEnough: true, isBrightEnough: true)
        #endif
    }

    #if os(iOS)
    private static func laplacianVariance(pixels: [UInt8], width: Int, height: Int) -> Float {
        guard width > 2, height > 2 else { return 0 }

        var sum: Double = 0
        var sumSquares: Double = 0
        var count = 0

        for y in 1..<(height - 1) {
            for x in 1..<(width - 1) {
                let center = Int(pixels[y * width + x])
                let top = Int(pixels[(y - 1) * width + x])
                let bottom = Int(pixels[(y + 1) * width + x])
                let left = Int(pixels[y * width + (x - 1)])
                let right = Int(pixels[y * width + (x + 1)])
                let laplacian = abs(4 * center - top - bottom - left - right)
                sum += Double(laplacian)
                sumSquares += Double(laplacian * laplacian)
                count += 1
            }
        }

        guard count > 0 else { return 0 }
        let mean = sum / Double(count)
        let variance = max(0, (sumSquares / Double(count)) - (mean * mean))
        return Float(variance)
    }

    private static func averageBrightness(pixels: [UInt8]) -> Float {
        guard !pixels.isEmpty else { return 0 }
        let total = pixels.reduce(0) { $0 + Int($1) }
        return Float(total) / Float(pixels.count) / 255.0
    }

    private static func brightnessPenalty(_ brightness: Float) -> Float {
        if brightness < PerceptionConfiguration.minimumBrightness { return brightness * 10 }
        if brightness > PerceptionConfiguration.maximumBrightness { return (1 - brightness) * 10 }
        return 1
    }
    #endif
}
