//
//  AnalysisService.swift
//  Perception Window
//

import CoreGraphics
import Foundation

struct AnalysisService {
    enum AnalysisError: Error {
        case missingAPIKey
        case invalidResponse
        case requestFailed(String)
    }

    private struct ObservationPayload: Decodable {
        let primary: String?
        let detail: String?
        let focusX: Double?
        let focusY: Double?
        let subject: String?
        let evidence: [String]?

        enum CodingKeys: String, CodingKey {
            case primary
            case detail
            case focusX = "focus_x"
            case focusY = "focus_y"
            case subject
            case evidence
        }
    }

    private struct ContinuityPayload: Decodable {
        let meaningfulChange: Bool?
        let observation: String?
        let detail: String?
        let evidence: [String]?
        let subjectMatchConfidence: Double?
        let focusX: Double?
        let focusY: Double?

        enum CodingKeys: String, CodingKey {
            case meaningfulChange = "meaningful_change"
            case observation
            case detail
            case evidence
            case subjectMatchConfidence = "subject_match_confidence"
            case focusX = "focus_x"
            case focusY = "focus_y"
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
        try await observe(jpeg: jpeg, identity: nil)
    }

    func observe(jpeg: Data, identity: SubjectIdentity?) async throws -> AnalysisResult {
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

        let rawResponse = try await performRequest(requestBody, apiKey: apiKey)
        guard let content = rawResponse.data(using: .utf8) else {
            throw AnalysisError.invalidResponse
        }

        let payload = try JSONDecoder().decode(ObservationPayload.self, from: content)
        return parseObservation(payload, rawResponse: rawResponse, identity: identity)
    }

    func compareContinuity(
        currentJPEG: Data,
        priorJPEG: Data,
        priorRecord: ObservationRecord,
        identity: SubjectIdentity
    ) async throws -> AnalysisResult {
        guard let apiKey = APIConfiguration.openAIAPIKey else {
            throw AnalysisError.missingAPIKey
        }

        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        let relative = formatter.localizedString(for: priorRecord.timestamp, relativeTo: Date())
        let priorSentence = priorRecord.userFacingSentence ?? "No prior sentence recorded."

        let requestBody = ChatCompletionRequest(
            model: APIConfiguration.model,
            messages: [
                .init(role: "system", content: .text(continuitySystemPrompt)),
                .init(role: "user", content: .parts([
                    .text("""
                    The user is looking at something familiar — not new to them.
                    Previous observation (\(relative)): \(priorSentence)

                    Image 1 is from the earlier visit. Image 2 is now.
                    What has meaningfully changed? Do not re-identify or re-introduce the subject.
                    """),
                    .imageURL("data:image/jpeg;base64,\(priorJPEG.base64EncodedString())"),
                    .imageURL("data:image/jpeg;base64,\(currentJPEG.base64EncodedString())")
                ]))
            ],
            responseFormat: .jsonObject,
            maxTokens: 260
        )

        let rawResponse = try await performRequest(requestBody, apiKey: apiKey, timeout: 45)
        guard let content = rawResponse.data(using: .utf8) else {
            throw AnalysisError.invalidResponse
        }

        let payload = try JSONDecoder().decode(ContinuityPayload.self, from: content)
        return parseContinuity(
            payload,
            rawResponse: rawResponse,
            identity: identity,
            comparisonTargetID: priorRecord.id
        )
    }

    private func performRequest(
        _ requestBody: ChatCompletionRequest,
        apiKey: String,
        timeout: TimeInterval = 30
    ) async throws -> String {
        var request = URLRequest(url: URL(string: "https://api.openai.com/v1/chat/completions")!)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(requestBody)
        request.timeoutInterval = timeout

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            let message = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw AnalysisError.requestFailed(message)
        }

        let completion = try JSONDecoder().decode(ChatCompletionResponse.self, from: data)
        guard let content = completion.choices.first?.message.content else {
            throw AnalysisError.invalidResponse
        }
        return content
    }

    private func parseObservation(
        _ payload: ObservationPayload,
        rawResponse: String,
        identity: SubjectIdentity?
    ) -> AnalysisResult {
        guard
            let primary = payload.primary?.trimmingCharacters(in: .whitespacesAndNewlines),
            !primary.isEmpty,
            !isSilenceResponse(primary)
        else {
            return .silent(.noMeaningfulChange, rawResponse: rawResponse, evidence: payload.evidence ?? [])
        }

        let detail = payload.detail?.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanedDetail = (detail?.isEmpty == false) ? detail : nil
        let primaryText = cleanedDetail.map { "\(primary). \($0)" } ?? primary

        let anchorX = payload.focusX ?? identity.map { Double($0.anchor.x) } ?? 0.5
        let anchorY = payload.focusY ?? identity.map { Double($0.anchor.y) } ?? 0.5

        let observation = PerceptionObservation(
            primary: primaryText,
            detail: cleanedDetail,
            entityID: identity?.persistentEntityID,
            temporarySubjectKey: identity?.temporarySubjectKey,
            domain: identity?.domain,
            anchor: CGPoint(x: anchorX, y: anchorY)
        )

        return AnalysisResult(
            outcome: .observation(observation),
            rawResponse: rawResponse,
            evidence: payload.evidence ?? []
        )
    }

    private func parseContinuity(
        _ payload: ContinuityPayload,
        rawResponse: String,
        identity: SubjectIdentity,
        comparisonTargetID: UUID
    ) -> AnalysisResult {
        let confidence = payload.subjectMatchConfidence ?? Double(identity.matchConfidence)
        let evidence = payload.evidence ?? []

        if payload.meaningfulChange == false {
            return .silent(
                .noMeaningfulChange,
                rawResponse: rawResponse,
                evidence: evidence,
                subjectMatchConfidence: confidence,
                comparisonTargetID: comparisonTargetID
            )
        }

        guard
            let primary = payload.observation?.trimmingCharacters(in: .whitespacesAndNewlines),
            !primary.isEmpty,
            !isSilenceResponse(primary)
        else {
            return .silent(
                .noMeaningfulChange,
                rawResponse: rawResponse,
                evidence: evidence,
                subjectMatchConfidence: confidence,
                comparisonTargetID: comparisonTargetID
            )
        }

        let detail = payload.detail?.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanedDetail = (detail?.isEmpty == false) ? detail : nil
        let primaryText = cleanedDetail.map { "\(primary). \($0)" } ?? primary

        let anchorX = payload.focusX ?? Double(identity.anchor.x)
        let anchorY = payload.focusY ?? Double(identity.anchor.y)

        let observation = PerceptionObservation(
            primary: primaryText,
            detail: cleanedDetail,
            entityID: identity.persistentEntityID,
            temporarySubjectKey: identity.temporarySubjectKey,
            domain: identity.domain,
            anchor: CGPoint(x: anchorX, y: anchorY)
        )

        return AnalysisResult(
            outcome: .observation(observation),
            rawResponse: rawResponse,
            evidence: evidence,
            subjectMatchConfidence: confidence,
            comparisonTargetID: comparisonTargetID
        )
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
            "none visible",
            "nothing changed",
            "no visible change",
            "no change",
            "unchanged",
            "same as before",
            "same as last"
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
        - Do not list multiple findings.
        - Do not describe the entire scene.
        - Do not reassure that everything looks fine.

        Respond as JSON only:
        {
          "primary": "string or null",
          "detail": "string or null",
          "evidence": ["short factual visual notes"],
          "focus_x": 0.0-1.0,
          "focus_y": 0.0-1.0,
          "subject": "internal retrieval hint only"
        }
        """
    }

    private var userPrompt: String {
        "Why might this be interesting to look at?"
    }

    private var continuitySystemPrompt: String {
        """
        You help someone notice what has changed since they last looked.

        The user already knows what they are looking at. Do not name, classify, or re-introduce the subject.
        Compare the two images honestly. It is correct and preferred to report no meaningful change.

        Your job is narrow:
        - Focus on visible change — growth, damage, new elements, shifted state.
        - If nothing meaningful has changed, set meaningful_change to false and observation to null.
        - Never pressure yourself to invent progress.
        - Never diagnose with certainty. Use tentative language.
        - Do not list multiple findings.

        Respond as JSON only:
        {
          "meaningful_change": true or false,
          "observation": "string or null",
          "detail": "string or null",
          "evidence": ["short factual visual notes about what you compared"],
          "subject_match_confidence": 0.0-1.0,
          "focus_x": 0.0-1.0,
          "focus_y": 0.0-1.0
        }
        """
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
