//
//  FramePreparation.swift
//  Perception Window
//

import CoreGraphics
import Foundation

#if os(iOS)
import UIKit
#endif

struct PreparedFrame: Equatable {
    /// Full-resolution frame selected during the hold — stored as evidence.
    let sourceJPEG: Data
    /// Cropped and resized frame intended for API upload.
    let analysisJPEG: Data
}

enum FramePreparation {
    /// Crop around ROI and resize before any API upload.
    static func prepare(sourceJPEG: Data, anchor: CGPoint) -> PreparedFrame? {
        #if os(iOS)
        guard let image = UIImage(data: sourceJPEG), let cgImage = image.cgImage else {
            return nil
        }

        let width = CGFloat(cgImage.width)
        let height = CGFloat(cgImage.height)
        let cropSide = min(width, height) * 0.72
        let centerX = anchor.x * width
        let centerY = anchor.y * height

        var cropRect = CGRect(
            x: centerX - cropSide / 2,
            y: centerY - cropSide / 2,
            width: cropSide,
            height: cropSide
        )
        cropRect = cropRect.intersection(CGRect(x: 0, y: 0, width: width, height: height))

        guard
            let cropped = cgImage.cropping(to: cropRect),
            let resized = resize(cgImage: cropped, maxDimension: PerceptionConfiguration.maxAnalysisImageDimension),
            let analysisJPEG = UIImage(cgImage: resized).jpegData(
                compressionQuality: PerceptionConfiguration.analysisJPEGQuality
            )
        else {
            return PreparedFrame(sourceJPEG: sourceJPEG, analysisJPEG: sourceJPEG)
        }

        return PreparedFrame(sourceJPEG: sourceJPEG, analysisJPEG: analysisJPEG)
        #else
        return PreparedFrame(sourceJPEG: sourceJPEG, analysisJPEG: sourceJPEG)
        #endif
    }

    #if os(iOS)
    private static func resize(cgImage: CGImage, maxDimension: Int) -> CGImage? {
        let width = cgImage.width
        let height = cgImage.height
        let longest = max(width, height)
        guard longest > maxDimension else { return cgImage }

        let scale = CGFloat(maxDimension) / CGFloat(longest)
        let newWidth = Int(CGFloat(width) * scale)
        let newHeight = Int(CGFloat(height) * scale)

        guard
            let colorSpace = cgImage.colorSpace,
            let context = CGContext(
                data: nil,
                width: newWidth,
                height: newHeight,
                bitsPerComponent: 8,
                bytesPerRow: 0,
                space: colorSpace,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            )
        else {
            return cgImage
        }

        context.interpolationQuality = .high
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: newWidth, height: newHeight))
        return context.makeImage()
    }
    #endif
}
