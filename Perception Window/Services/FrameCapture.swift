//
//  FrameCapture.swift
//  Perception Window
//

import AVFoundation
import CoreImage
import ImageIO
import UniformTypeIdentifiers

#if os(iOS)
import UIKit
#endif

enum FrameCapture {
    static func jpeg(from sampleBuffer: CMSampleBuffer, quality: CGFloat = 0.88) -> Data? {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return nil }

        let ciImage = CIImage(cvPixelBuffer: pixelBuffer)
        let context = CIContext(options: nil)

        guard let cgImage = context.createCGImage(ciImage, from: ciImage.extent) else { return nil }

        #if os(iOS)
        let orientation = imageOrientation(for: sampleBuffer)
        let image = UIImage(cgImage: cgImage, scale: 1, orientation: orientation)
        return image.jpegData(compressionQuality: quality)
        #else
        return jpegData(from: cgImage, quality: quality)
        #endif
    }

    #if os(iOS)
    private static func imageOrientation(for sampleBuffer: CMSampleBuffer) -> UIImage.Orientation {
        guard
            let attachments = CMCopyDictionaryOfAttachments(
                allocator: kCFAllocatorDefault,
                target: sampleBuffer,
                attachmentMode: kCMAttachmentMode_ShouldPropagate
            ) as? [String: Any],
            let rawValue = attachments[kCGImagePropertyOrientation as String] as? UInt32,
            let cgOrientation = CGImagePropertyOrientation(rawValue: rawValue)
        else {
            return .right
        }

        switch cgOrientation {
        case .up: return .up
        case .upMirrored: return .upMirrored
        case .down: return .down
        case .downMirrored: return .downMirrored
        case .left: return .left
        case .leftMirrored: return .leftMirrored
        case .right: return .right
        case .rightMirrored: return .rightMirrored
        }
    }
    #endif

    private static func jpegData(from cgImage: CGImage, quality: CGFloat) -> Data? {
        let data = NSMutableData()
        guard
            let destination = CGImageDestinationCreateWithData(
                data,
                UTType.jpeg.identifier as CFString,
                1,
                nil
            )
        else {
            return nil
        }

        CGImageDestinationAddImage(
            destination,
            cgImage,
            [kCGImageDestinationLossyCompressionQuality: quality] as CFDictionary
        )
        guard CGImageDestinationFinalize(destination) else { return nil }
        return data as Data
    }
}
