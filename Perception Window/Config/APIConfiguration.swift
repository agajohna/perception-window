//
//  APIConfiguration.swift
//  Perception Window
//

import Foundation

enum APIConfiguration {
    static var openAIAPIKey: String? {
        if let envKey = ProcessInfo.processInfo.environment["OPENAI_API_KEY"],
           !envKey.isEmpty {
            return envKey
        }

        guard
            let path = Bundle.main.path(forResource: "Secrets", ofType: "plist"),
            let dict = NSDictionary(contentsOfFile: path) as? [String: Any],
            let key = dict["OPENAI_API_KEY"] as? String,
            !key.isEmpty,
            key != "your-api-key-here"
        else {
            return nil
        }

        return key
    }

    static let model = "gpt-4o"
    static let modelVersion = "2026-08"
}
