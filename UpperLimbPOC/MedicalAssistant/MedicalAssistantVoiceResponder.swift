import Foundation

actor MedicalAssistantVoiceResponder: VoiceAssistantResponding {
    private let modelClient: AppleFoundationModelClient
    private let knowledgeRepository: MedicalKnowledgeRepository
    private let safetyPolicy: MedicalSafetyPolicy

    init(
        modelClient: AppleFoundationModelClient = AppleFoundationModelClient(),
        knowledgeRepository: MedicalKnowledgeRepository = MedicalKnowledgeRepository(),
        safetyPolicy: MedicalSafetyPolicy = MedicalSafetyPolicy()
    ) {
        self.modelClient = modelClient
        self.knowledgeRepository = knowledgeRepository
        self.safetyPolicy = safetyPolicy
    }

    func availability() async -> AssistantOnDeviceAvailability {
        await modelClient.availability()
    }

    func respond(
        to transcript: String,
        context: VoiceAssistantContextSnapshot
    ) async throws -> String {
        switch safetyPolicy.evaluate(transcript) {
        case let .reject(message):
            throw VoiceAssistantBackendError.questionRejected(message)
        case let .localResponse(message):
            return message
        case .allow:
            break
        }

        let anatomyContext = AssistantAnatomyContext(
            regionName: context.regionName,
            laterality: context.laterality,
            focusedStructure: context.focusedAnnotationLabel
                ?? defaultFocusedStructure(for: context.revealState),
            educationalSource: "Generic CT-derived educational reference model; not patient-specific"
        )
        let knowledge = knowledgeRepository.retrieve(
            query: transcript,
            anatomyContext: anatomyContext
        )
        let basePrompt = safetyPolicy.systemPrompt(
            audience: context.audience,
            anatomyContext: anatomyContext,
            knowledge: knowledge
        )
        let prompt = """
        \(basePrompt)

        VOICE RESPONSE
        - This is an explicit push-to-talk exchange. The transcript is ephemeral.
        - Answer in concise, natural spoken language. Do not use Markdown formatting.
        - Limit the answer to educational FAQ or app-navigation explanation.
        - Do not diagnose, recommend treatment, interpret patient-specific findings,
          or claim that a model feature is available unless the read-only context says so.

        READ-ONLY EDUCATIONAL SESSION CONTEXT
        Demo case label: \(context.educationalCaseName)
        Selected model: \(context.modelName)
        Reveal state: \(context.revealState.rawValue)
        Focused annotation: \(context.focusedAnnotationLabel ?? "none")
        """

        do {
            return try await modelClient.complete(
                systemPrompt: prompt,
                conversation: [AssistantMessage(
                    role: .user,
                    text: transcript
                )]
            )
        } catch let error as AppleFoundationModelError {
            throw VoiceAssistantBackendError.response(
                error.localizedDescription
            )
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            throw VoiceAssistantBackendError.response(
                "The on-device educational assistant could not answer. Try again."
            )
        }
    }

    private func defaultFocusedStructure(
        for revealState: VoiceAssistantRevealState
    ) -> String {
        switch revealState {
        case .surface:
            "Right forearm surface anatomy"
        case .mixed:
            "Right forearm soft tissue, radius, and ulna"
        case .bone:
            "Right radius and ulna"
        }
    }
}
