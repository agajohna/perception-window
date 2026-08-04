//
//  PixelBufferCopier.swift
//  Perception Window
//

import CoreVideo
import Foundation

#if os(iOS)

enum PixelBufferCopier {
    private static let metalCompatibleAttributes: CFDictionary = {
        [
            kCVPixelBufferMetalCompatibilityKey as String: true,
            kCVPixelBufferIOSurfacePropertiesKey as String: [:] as [String: Any],
        ] as NSDictionary
    }()

    /// Copy a camera pixel buffer so ARKit can release the parent `ARFrame` immediately.
    static func copy(_ source: CVPixelBuffer) -> CVPixelBuffer? {
        let width = CVPixelBufferGetWidth(source)
        let height = CVPixelBufferGetHeight(source)
        let format = CVPixelBufferGetPixelFormatType(source)

        var destination: CVPixelBuffer?
        let status = CVPixelBufferCreate(
            kCFAllocatorDefault,
            width,
            height,
            format,
            metalCompatibleAttributes,
            &destination
        )
        guard status == kCVReturnSuccess, let destination else { return nil }

        CVPixelBufferLockBaseAddress(source, .readOnly)
        CVPixelBufferLockBaseAddress(destination, [])
        defer {
            CVPixelBufferUnlockBaseAddress(destination, [])
            CVPixelBufferUnlockBaseAddress(source, .readOnly)
        }

        if CVPixelBufferIsPlanar(source) {
            let planeCount = CVPixelBufferGetPlaneCount(source)
            guard planeCount == CVPixelBufferGetPlaneCount(destination) else { return nil }

            for plane in 0..<planeCount {
                guard
                    let sourceBase = CVPixelBufferGetBaseAddressOfPlane(source, plane),
                    let destinationBase = CVPixelBufferGetBaseAddressOfPlane(destination, plane)
                else {
                    return nil
                }

                let planeHeight = CVPixelBufferGetHeightOfPlane(source, plane)
                let sourceRowBytes = CVPixelBufferGetBytesPerRowOfPlane(source, plane)
                let destinationRowBytes = CVPixelBufferGetBytesPerRowOfPlane(destination, plane)
                let copyWidth = min(sourceRowBytes, destinationRowBytes)

                for row in 0..<planeHeight {
                    memcpy(
                        destinationBase.advanced(by: row * destinationRowBytes),
                        sourceBase.advanced(by: row * sourceRowBytes),
                        copyWidth
                    )
                }
            }
        } else {
            guard
                let sourceBase = CVPixelBufferGetBaseAddress(source),
                let destinationBase = CVPixelBufferGetBaseAddress(destination)
            else {
                return nil
            }

            let sourceRowBytes = CVPixelBufferGetBytesPerRow(source)
            let destinationRowBytes = CVPixelBufferGetBytesPerRow(destination)
            let copyWidth = min(sourceRowBytes, destinationRowBytes)

            for row in 0..<height {
                memcpy(
                    destinationBase.advanced(by: row * destinationRowBytes),
                    sourceBase.advanced(by: row * sourceRowBytes),
                    copyWidth
                )
            }
        }

        if let attachments = CVBufferCopyAttachments(source, .shouldPropagate) {
            CVBufferSetAttachments(destination, attachments, .shouldPropagate)
        }

        return destination
    }
}

#endif
