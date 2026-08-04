//
//  CameraCaptureMetadata.swift
//  Perception Window
//

import Foundation

struct CameraCaptureMetadata: Codable, Equatable {
    let captureDate: Date
    let imageWidth: Int?
    let imageHeight: Int?
    let jpegByteCount: Int

    init(captureDate: Date = Date(), imageWidth: Int? = nil, imageHeight: Int? = nil, jpegByteCount: Int) {
        self.captureDate = captureDate
        self.imageWidth = imageWidth
        self.imageHeight = imageHeight
        self.jpegByteCount = jpegByteCount
    }
}
