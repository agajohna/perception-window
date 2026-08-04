//
//  PlaceContext.swift
//  Perception Window
//

import Foundation

/// Placefulness emerges over time — reserved for future location and naming signals.
struct PlaceContext: Codable, Equatable {
    let placeName: String?
    let visitCountAtPlace: Int?

    init(placeName: String? = nil, visitCountAtPlace: Int? = nil) {
        self.placeName = placeName
        self.visitCountAtPlace = visitCountAtPlace
    }
}
