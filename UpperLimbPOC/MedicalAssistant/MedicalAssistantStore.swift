import Foundation

@MainActor
final class MedicalAssistantStore: ObservableObject {
    @Published var provider: AssistantProvider {
        didSet {
            UserDefaults.standard.set(
                provider.rawValue,
                forKey: Self.providerPreferenceKey
            )
            errorMessage = nil
            if provider == .onDevice {
                Task { await refreshOnDeviceAvailability() }
            }
        }
    }
    @Published var audience: AssistantAudience = .patient {
        didSet { persistConversationIfNeeded() }
    }
    @Published var draft = ""
    @Published private(set) var messages: [AssistantMessage] = []
    @Published private(set) var activity: AssistantActivity = .idle
    @Published private(set) var errorMessage: String?
    @Published private(set) var isAPIKeyConfigured = false
    @Published private(set) var onDeviceAvailability: AssistantOnDeviceAvailability = .checking
    @Published var isShowingSettings = false
    @Published private(set) var remembersConversations: Bool

    private let transport: OpenAICompatibleClient
    private let onDeviceTransport: AppleFoundationModelClient
    private let credentialStore: AssistantCredentialStore
    private let conversationRepository: AssistantConversationRepository
    private let knowledgeRepository: MedicalKnowledgeRepository
    private let safetyPolicy: MedicalSafetyPolicy
    private var activeTask: Task<Void, Never>?
    private var persistenceTask: Task<Void, Never>?
    private var lastFailedInput: String?
    private var isPrepared = false

    private static let persistencePreferenceKey =
        "MedicalAssistant.RememberConversations"
    private static let providerPreferenceKey =
        "MedicalAssistant.Provider"

    var canRetryLastRequest: Bool {
        lastFailedInput != nil
            && activity == .idle
            && isSelectedProviderAvailable
    }

    var isSelectedProviderAvailable: Bool {
        switch provider {
        case .onDevice:
            onDeviceAvailability.isAvailable
        case .cloud:
            isAPIKeyConfigured
        }
    }

    var providerStatus: String {
        switch provider {
        case .onDevice:
            onDeviceAvailability.label
        case .cloud:
            isAPIKeyConfigured ? "API key configured" : "API key required"
        }
    }

    init(
        transport: OpenAICompatibleClient = OpenAICompatibleClient(),
        onDeviceTransport: AppleFoundationModelClient = AppleFoundationModelClient(),
        credentialStore: AssistantCredentialStore = AssistantCredentialStore(),
        conversationRepository: AssistantConversationRepository = AssistantConversationRepository(),
        knowledgeRepository: MedicalKnowledgeRepository = MedicalKnowledgeRepository(),
        safetyPolicy: MedicalSafetyPolicy = MedicalSafetyPolicy()
    ) {
        provider = UserDefaults.standard.string(
            forKey: Self.providerPreferenceKey
        ).flatMap(AssistantProvider.init(rawValue:)) ?? .onDevice
        self.transport = transport
        self.onDeviceTransport = onDeviceTransport
        self.credentialStore = credentialStore
        self.conversationRepository = conversationRepository
        self.knowledgeRepository = knowledgeRepository
        self.safetyPolicy = safetyPolicy
        remembersConversations = UserDefaults.standard.bool(
            forKey: Self.persistencePreferenceKey
        )
    }

    func prepare() async {
        guard !isPrepared else { return }
        isPrepared = true

        do {
#if DEBUG
            if try credentialStore.loadAPIKey() == nil,
               let developmentKey = ProcessInfo.processInfo.environment[
                   "UPPER_LIMB_ASSISTANT_API_KEY"
               ],
               !developmentKey.isEmpty {
                try credentialStore.saveAPIKey(developmentKey)
            }
#endif
            isAPIKeyConfigured = try credentialStore.loadAPIKey() != nil
        } catch {
            errorMessage = error.localizedDescription
        }

        await refreshOnDeviceAvailability()

        if remembersConversations {
            do {
                if let snapshot = try await conversationRepository.load() {
                    audience = snapshot.audience
                    messages = Array(snapshot.messages.suffix(60))
                }
            } catch {
                errorMessage = "Saved conversation could not be opened."
            }
        }

        if provider == .cloud && !isAPIKeyConfigured {
            isShowingSettings = true
        }
    }

    func refreshOnDeviceAvailability() async {
        onDeviceAvailability = .checking
        onDeviceAvailability = await onDeviceTransport.availability()
    }

    func send(anatomyContext: AssistantAnatomyContext) {
        guard activity == .idle else { return }
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)

        switch safetyPolicy.evaluate(text) {
        case let .reject(message):
            errorMessage = message
            return
        case let .localResponse(message):
            errorMessage = nil
            draft = ""
            messages.append(AssistantMessage(role: .user, text: text))
            messages.append(AssistantMessage(
                role: .assistant,
                text: message,
                isLocalSafetyResponse: true
            ))
            persistConversationIfNeeded()
            return
        case .allow:
            break
        }

        guard isSelectedProviderAvailable else {
            errorMessage = provider == .cloud
                ? "Configure the cloud API key before sending this question."
                : onDeviceAvailability.userFacingMessage
            isShowingSettings = true
            return
        }

        draft = ""
        errorMessage = nil
        messages.append(AssistantMessage(role: .user, text: text))
        persistConversationIfNeeded()
        startRequest(
            input: text,
            anatomyContext: anatomyContext,
            provider: provider
        )
    }

    func retryLastRequest(anatomyContext: AssistantAnatomyContext) {
        guard activity == .idle,
              isSelectedProviderAvailable,
              let lastFailedInput
        else { return }
        errorMessage = nil
        startRequest(
            input: lastFailedInput,
            anatomyContext: anatomyContext,
            provider: provider
        )
    }

    func cancelRequest() {
        activeTask?.cancel()
    }

    func startNewConversation() {
        activeTask?.cancel()
        activeTask = nil
        activity = .idle
        messages = []
        errorMessage = nil
        lastFailedInput = nil
        persistenceTask?.cancel()
        persistenceTask = Task { [conversationRepository] in
            try? await conversationRepository.delete()
        }
    }

    func saveAPIKey(_ value: String) -> Bool {
        do {
            try credentialStore.saveAPIKey(value)
            isAPIKeyConfigured = true
            errorMessage = nil
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    func deleteAPIKey() {
        do {
            try credentialStore.deleteAPIKey()
            isAPIKeyConfigured = false
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func setRemembersConversations(_ enabled: Bool) {
        remembersConversations = enabled
        UserDefaults.standard.set(enabled, forKey: Self.persistencePreferenceKey)
        if enabled {
            persistConversationIfNeeded()
        } else {
            persistenceTask?.cancel()
            persistenceTask = Task { [conversationRepository] in
                try? await conversationRepository.delete()
            }
        }
    }

    private func startRequest(
        input: String,
        anatomyContext: AssistantAnatomyContext,
        provider: AssistantProvider
    ) {
        activity = .waitingForResponse
        lastFailedInput = input
        activeTask = Task { [weak self] in
            await self?.performRequest(
                input: input,
                anatomyContext: anatomyContext,
                provider: provider
            )
        }
    }

    private func performRequest(
        input: String,
        anatomyContext: AssistantAnatomyContext,
        provider: AssistantProvider
    ) async {
        let responseID = UUID()
        defer {
            activity = .idle
            activeTask = nil
        }

        do {
            let knowledge = knowledgeRepository.retrieve(
                query: input,
                anatomyContext: anatomyContext
            )
            let prompt = safetyPolicy.systemPrompt(
                audience: audience,
                anatomyContext: anatomyContext,
                knowledge: knowledge
            )
            let conversation = boundedConversation(for: provider)
            let cloudAPIKey: String?
            if provider == .cloud {
                guard let apiKey = try credentialStore.loadAPIKey() else {
                    isAPIKeyConfigured = false
                    isShowingSettings = true
                    errorMessage = "Configure the cloud API key to send this question."
                    return
                }
                cloudAPIKey = apiKey
            } else {
                cloudAPIKey = nil
            }

            messages.append(AssistantMessage(
                id: responseID,
                role: .assistant,
                text: ""
            ))

            let answer: String
            switch provider {
            case .onDevice:
                answer = try await onDeviceTransport.completeStreaming(
                    systemPrompt: prompt,
                    conversation: conversation
                ) { [weak self] partial in
                    await self?.updateStreamingResponse(
                        id: responseID,
                        text: partial
                    )
                }
            case .cloud:
                guard let cloudAPIKey else {
                    throw AssistantTransportError.invalidResponse
                }
                answer = try await transport.completeStreaming(
                    systemPrompt: prompt,
                    conversation: conversation,
                    apiKey: cloudAPIKey
                ) { [weak self] partial in
                    await self?.updateStreamingResponse(
                        id: responseID,
                        text: partial
                    )
                }
            }
            try Task.checkCancellation()

            updateStreamingResponse(
                id: responseID,
                text: answer,
                citations: safetyPolicy.citedSources(
                    in: answer,
                    from: knowledge
                )
            )
            lastFailedInput = nil
            errorMessage = nil
            persistConversationIfNeeded()
        } catch is CancellationError {
            removeStreamingResponse(id: responseID)
            errorMessage = nil
        } catch {
            removeStreamingResponse(id: responseID)
            if let onDeviceError = error as? AppleFoundationModelError,
               onDeviceError.indicatesModelNotReady {
                onDeviceAvailability = .modelNotReady
            }
            errorMessage = friendlyErrorMessage(for: error)
        }
    }

    private func updateStreamingResponse(
        id: UUID,
        text: String,
        citations: [AssistantCitation]? = nil
    ) {
        guard let index = messages.firstIndex(where: { $0.id == id }) else {
            return
        }
        let existing = messages[index]
        messages[index] = AssistantMessage(
            id: existing.id,
            role: .assistant,
            text: text,
            createdAt: existing.createdAt,
            citations: citations ?? existing.citations,
            isLocalSafetyResponse: false
        )
    }

    private func removeStreamingResponse(id: UUID) {
        messages.removeAll { $0.id == id }
    }

    private func boundedConversation(
        for provider: AssistantProvider
    ) -> [AssistantMessage] {
        var result: [AssistantMessage] = []
        var characterCount = 0
        let messageLimit = provider == .onDevice ? 8 : 16
        let characterLimit = provider == .onDevice ? 6_000 : 12_000

        for message in messages.reversed() {
            guard result.count < messageLimit,
                  characterCount + message.text.count <= characterLimit
            else { break }
            result.append(message)
            characterCount += message.text.count
        }
        return result.reversed()
    }

    private func persistConversationIfNeeded() {
        guard remembersConversations else { return }
        let snapshot = AssistantConversationSnapshot(
            audience: audience,
            messages: Array(messages.suffix(60))
        )
        persistenceTask?.cancel()
        persistenceTask = Task { [conversationRepository] in
            try? await conversationRepository.save(snapshot)
        }
    }

    private func friendlyErrorMessage(for error: Error) -> String {
        if let urlError = error as? URLError {
            switch urlError.code {
            case .notConnectedToInternet, .networkConnectionLost:
                return "No network connection. Reconnect and try again."
            case .timedOut:
                return "The assistant service timed out. Try again."
            default:
                return "The assistant service could not be reached. Try again."
            }
        }
        return error.localizedDescription
    }
}

extension AssistantAnatomyContext {
    @MainActor
    init(overlay: OverlayState) {
        let laterality: String
        if overlay.selectedRegion.rawValue.hasPrefix("left") {
            laterality = "left"
        } else if overlay.selectedRegion.rawValue.hasPrefix("right") {
            laterality = "right"
        } else {
            laterality = "not specified"
        }

        self.init(
            regionName: overlay.selectedRegion.name,
            laterality: laterality,
            focusedStructure: overlay.focusedBoneName,
            educationalSource: "Bundled generic anatomy model metadata; not patient-specific"
        )
    }
}
