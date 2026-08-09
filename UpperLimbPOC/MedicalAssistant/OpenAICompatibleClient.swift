import Foundation

enum AssistantTransportError: LocalizedError {
    case invalidResponse
    case httpStatus(Int, String)
    case emptyResponse
    case responseTooLarge

    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            "The assistant service returned an invalid response."
        case let .httpStatus(code, message):
            message.isEmpty
                ? "The assistant service returned HTTP \(code)."
                : message
        case .emptyResponse:
            "The assistant service returned an empty answer."
        case .responseTooLarge:
            "The assistant response exceeded the app's safety limit."
        }
    }
}

actor OpenAICompatibleClient {
    private struct RequestMessage: Encodable {
        let role: String
        let content: String
    }

    private struct CompletionRequest: Encodable {
        let model: String
        let messages: [RequestMessage]
        let stream = false
    }

    private struct CompletionResponse: Decodable {
        struct Choice: Decodable {
            struct Message: Decodable {
                let content: String?
            }

            let message: Message
        }

        let choices: [Choice]
    }

    private struct ErrorEnvelope: Decodable {
        struct APIError: Decodable {
            let message: String?
        }

        let error: APIError?
    }

    private let configuration: MedicalAssistantConfiguration
    private let session: URLSession
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init(configuration: MedicalAssistantConfiguration = .live) {
        self.configuration = configuration
        let sessionConfiguration = URLSessionConfiguration.ephemeral
        sessionConfiguration.timeoutIntervalForRequest = configuration.requestTimeout
        sessionConfiguration.timeoutIntervalForResource = configuration.requestTimeout
        sessionConfiguration.requestCachePolicy = .reloadIgnoringLocalCacheData
        sessionConfiguration.waitsForConnectivity = true
        session = URLSession(configuration: sessionConfiguration)
    }

    func complete(
        systemPrompt: String,
        conversation: [AssistantMessage],
        apiKey: String
    ) async throws -> String {
        var requestMessages = [RequestMessage(role: "system", content: systemPrompt)]
        requestMessages.append(contentsOf: conversation.map {
            RequestMessage(role: $0.role.rawValue, content: $0.text)
        })

        var request = URLRequest(url: configuration.chatCompletionsURL)
        request.httpMethod = "POST"
        request.timeoutInterval = configuration.requestTimeout
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.httpBody = try encoder.encode(CompletionRequest(
            model: configuration.model,
            messages: requestMessages
        ))

        let (data, response) = try await session.data(for: request)
        try Task.checkCancellation()

        guard let httpResponse = response as? HTTPURLResponse else {
            throw AssistantTransportError.invalidResponse
        }
        guard (200..<300).contains(httpResponse.statusCode) else {
            let envelope = try? decoder.decode(ErrorEnvelope.self, from: data)
            throw AssistantTransportError.httpStatus(
                httpResponse.statusCode,
                envelope?.error?.message ?? ""
            )
        }

        let completion = try decoder.decode(CompletionResponse.self, from: data)
        guard let content = completion.choices.first?.message.content?
            .trimmingCharacters(in: .whitespacesAndNewlines),
              !content.isEmpty
        else {
            throw AssistantTransportError.emptyResponse
        }
        guard content.count <= 20_000 else {
            throw AssistantTransportError.responseTooLarge
        }
        return content
    }
}
