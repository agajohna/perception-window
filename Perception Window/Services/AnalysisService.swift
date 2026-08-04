//
//  AnalysisService.swift
//  Perception Window
//

import Foundation

struct AnalysisService {
    enum AnalysisError: Error {
        case missingAPIKey
        case invalidResponse
        case requestFailed(String)
    }

    private struct ModelPayload: Decodable {
        let primary: String?
        let detail: String?
        let focusX: Double?
        let focusY: Double?
        let subject: String?

        enum CodingKeys: String, CodingKey {
            case primary
            case detail
            case focusX = "focus_x"
            case focusY = "focus_y"
            case subject
        }
    }

    private struct ChatCompletionResponse: Decodable {
        struct Choice: Decodable {
            struct Message: Decodable {
                let content: String
            }

            let message: Message
        }

        let choices: [Choice]
    }

    func analyze(jpeg: Data) async throws -> AnalysisResult {
        guard let apiKey = APIConfiguration.openAIAPIKey else {
            throw AnalysisError.missingAPIKey
        }

        let base64 = jpeg.base64EncodedString()
        let requestBody = ChatCompletionRequest(
            model: APIConfiguration.model,
            messages: [
                .init(role: "system", content: .text(systemPrompt)),
                .init(role: "user", content: .parts([
                    .text(userPrompt),
                    .imageURL("data:image/jpeg;base64,\(base64)")
                ]))
            ],
            responseFormat: .jsonObject,
            maxTokens: 220
        )

        var request = URLRequest(url: URL(string: "https://api.openai.com/v1/chat/completions")!)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(requestBody)
        request.timeoutInterval = 30

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let http = response as? HTTPURLResponse else {
            throw AnalysisError.invalidResponse
        }

        guard (200...299).contains(http.statusCode) else {
            let message = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw AnalysisError.requestFailed(message)
        }

        let completion = try JSONDecoder().decode(ChatCompletionResponse.self, from: data)
        guard let content = completion.choices.first?.message.content.data(using: .utf8) else {
            throw AnalysisError.invalidResponse
        }

        let payload = try JSONDecoder().decode(ModelPayload.self, from: content)
        return parse(payload, rawResponse: completion.choices.first?.message.content ?? "")
    }

    private func parse(_ payload: ModelPayload, rawResponse: String) -> AnalysisResult {
        guard
            let primary = payload.primary?.trimmingCharacters(in: .whitespacesAndNewlines),
            !primary.isEmpty,
            !isSilenceResponse(primary)
        else {
            return AnalysisResult(outcome: .nothingVisible, rawResponse: rawResponse)
        }

        let detail = payload.detail?.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanedDetail = (detail?.isEmpty == false) ? detail : nil

        if let detail = cleanedDetail, isSilenceResponse(detail) {
            return AnalysisResult(outcome: .nothingVisible, rawResponse: rawResponse)
        }

        // One observation only — detail is folded into primary when present.
        let primaryText = cleanedDetail.map { "\(primary). \($0)" } ?? primary

        let anchorX = payload.focusX ?? 0.5
        let anchorY = payload.focusY ?? 0.5

        let observation = PerceptionObservation(
            primary: primaryText,
            detail: cleanedDetail,
            subject: payload.subject?.trimmingCharacters(in: .whitespacesAndNewlines),
            domain: nil,
            anchor: CGPoint(x: anchorX, y: anchorY)
        )

        return AnalysisResult(outcome: .observation(observation), rawResponse: rawResponse)
    }

    private func isSilenceResponse(_ text: String) -> Bool {
        let normalized = text.lowercased()
        let silencePhrases = [
            "nothing_visible",
            "nothing unusual",
            "no issues",
            "no issue",
            "nothing to report",
            "looks healthy",
            "look healthy",
            "appears healthy",
            "everything looks",
            "nothing noteworthy",
            "nothing notable",
            "no finding",
            "no findings",
            "none visible"
        ]
        return silencePhrases.contains { normalized.contains($0) }
    }

    private var systemPrompt: String {
        """
        You help someone notice what is worth seeing in the world.

        The user points their phone at something. Do not name or classify the object first.
        Answer why it might be interesting to look at right now.

        Your job is narrow:
        - Look at what is nearest the center of the frame.
        - Return one observation about why this is worth noticing.
        - If nothing is reasonably worth saying, return primary as null.
        - Never diagnose with certainty. Use tentative language.
        - Do not assign numeric confidence.
        - Do not list multiple findings.
        - Do not describe the entire scene.
        - Do not reassure that everything looks fine.

        Good examples:
        primary: "New flower bud emerging"
        primary: "This shoot may originate below the graft union"
        primary: "Possible early chlorosis"
        primary: "Uneven yellowing on older leaves"

        Bad examples (too much like object ID):
        primary: "Coffee plant"
        primary: "Printer"
        primary: "Leaf"

        Respond as JSON only:
        {
          "primary": "string or null",
          "detail": "string or null",
          "focus_x": 0.0-1.0,
          "focus_y": 0.0-1.0,
          "subject": "internal only, not shown to user"
        }

        focus_x and focus_y mark where the observation applies, origin top-left.
        """
    }

    private var userPrompt: String {
        "Why might this be interesting to look at?"
    }
}

// MARK: - OpenAI request types

private struct ChatCompletionRequest: Encodable {
    struct Message: Encodable {
        enum Content: Encodable {
            case text(String)
            case parts([ContentPart])

            func encode(to encoder: Encoder) throws {
                var container = encoder.singleValueContainer()
                switch self {
                case .text(let value):
                    try container.encode(value)
                case .parts(let parts):
                    try container.encode(parts)
                }
            }
        }

        struct ContentPart: Encodable {
            let type: String
            let text: String?
            let imageURL: ImageURL?

            enum CodingKeys: String, CodingKey {
                case type
                case text
                case imageURL = "image_url"
            }

            func encode(to encoder: Encoder) throws {
                var container = encoder.container(keyedBy: CodingKeys.self)
                try container.encode(type, forKey: .type)
                if let text {
                    try container.encode(text, forKey: .text)
                }
                if let imageURL {
                    try container.encode(imageURL, forKey: .imageURL)
                }
            }

            static func text(_ value: String) -> ContentPart {
                ContentPart(type: "text", text: value, imageURL: nil)
            }

            static func imageURL(_ value: String) -> ContentPart {
                ContentPart(type: "image_url", text: nil, imageURL: ImageURL(url: value))
            }
        }

        struct ImageURL: Encodable {
            let url: String
        }

        let role: String
        let content: Content
    }

    struct ResponseFormat: Encodable {
        let type: String
    }

    let model: String
    let messages: [Message]
    let responseFormat: ResponseFormat
    let maxTokens: Int

    enum CodingKeys: String, CodingKey {
        case model
        case messages
        case responseFormat = "response_format"
        case maxTokens = "max_tokens"
    }
}

private extension ChatCompletionRequest.ResponseFormat {
    static var jsonObject: Self {
        Self(type: "json_object")
    }
}
