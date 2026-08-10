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
        let stream: Bool
    }

    private struct StreamingCompletionResponse: Decodable {
        struct Choice: Decodable {
            struct Delta: Decodable {
                let content: String?
            }

            let delta: Delta
        }

        let choices: [Choice]
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
        let request = try makeRequest(
            systemPrompt: systemPrompt,
            conversation: conversation,
            apiKey: apiKey,
            stream: false
        )

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

    func completeStreaming(
        systemPrompt: String,
        conversation: [AssistantMessage],
        apiKey: String,
        onPartial: @escaping @Sendable (String) async -> Void
    ) async throws -> String {
        let request = try makeRequest(
            systemPrompt: systemPrompt,
            conversation: conversation,
            apiKey: apiKey,
            stream: true
        )
        let (bytes, response) = try await session.bytes(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw AssistantTransportError.invalidResponse
        }
        guard (200..<300).contains(httpResponse.statusCode) else {
            var errorData = Data()
            for try await byte in bytes {
                guard errorData.count < 20_000 else { break }
                errorData.append(byte)
            }
            let envelope = try? decoder.decode(ErrorEnvelope.self, from: errorData)
            throw AssistantTransportError.httpStatus(
                httpResponse.statusCode,
                envelope?.error?.message ?? ""
            )
        }

        var content = ""
        var plainResponseData = Data()
        var receivedStreamingEvent = false

        for try await line in bytes.lines {
            try Task.checkCancellation()
            guard !line.isEmpty else { continue }

            guard line.hasPrefix("data:") else {
                plainResponseData.append(contentsOf: line.utf8)
                plainResponseData.append(0x0A)
                continue
            }

            receivedStreamingEvent = true
            let payload = line.dropFirst(5).trimmingCharacters(
                in: .whitespaces
            )
            if payload == "[DONE]" { break }
            guard let data = payload.data(using: .utf8),
                  let event = try? decoder.decode(
                    StreamingCompletionResponse.self,
                    from: data
                  ),
                  let delta = event.choices.first?.delta.content,
                  !delta.isEmpty
            else { continue }

            content += delta
            guard content.count <= 20_000 else {
                throw AssistantTransportError.responseTooLarge
            }
            await onPartial(content)
        }

        if !receivedStreamingEvent,
           let completion = try? decoder.decode(
            CompletionResponse.self,
            from: plainResponseData
           ),
           let fallback = completion.choices.first?.message.content {
            content = fallback
        }

        content = content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !content.isEmpty else {
            throw AssistantTransportError.emptyResponse
        }
        guard content.count <= 20_000 else {
            throw AssistantTransportError.responseTooLarge
        }
        await onPartial(content)
        return content
    }

    private func makeRequest(
        systemPrompt: String,
        conversation: [AssistantMessage],
        apiKey: String,
        stream: Bool
    ) throws -> URLRequest {
        var requestMessages = [RequestMessage(
            role: "system",
            content: systemPrompt
        )]
        requestMessages.append(contentsOf: conversation.map {
            RequestMessage(role: $0.role.rawValue, content: $0.text)
        })

        var request = URLRequest(url: configuration.chatCompletionsURL)
        request.httpMethod = "POST"
        request.timeoutInterval = configuration.requestTimeout
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("text/event-stream", forHTTPHeaderField: "Accept")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.httpBody = try encoder.encode(CompletionRequest(
            model: configuration.model,
            messages: requestMessages,
            stream: stream
        ))
        return request
    }
}
