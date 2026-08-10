import Foundation

@MainActor
final class VoiceAssistantController: ObservableObject {
    @Published private(set) var state: VoiceAssistantState = .unavailable(.notPrepared)

    private let transcriber: any VoiceAssistantTranscribing
    private let responder: any VoiceAssistantResponding
    private let speaker: any VoiceAssistantSpeaking
    private let contextProvider: any VoiceAssistantContextProviding
    private let enablementProvider: any VoiceAssistantEnablementProviding
    private let locale: Locale
    private var operationID = UUID()

    init(
        transcriber: any VoiceAssistantTranscribing,
        responder: any VoiceAssistantResponding,
        speaker: any VoiceAssistantSpeaking,
        contextProvider: any VoiceAssistantContextProviding,
        enablementProvider: any VoiceAssistantEnablementProviding,
        locale: Locale = .current
    ) {
        self.transcriber = transcriber
        self.responder = responder
        self.speaker = speaker
        self.contextProvider = contextProvider
        self.enablementProvider = enablementProvider
        self.locale = locale
    }

    func prepare() async {
        let operation = beginOperation()
        guard await enablementProvider.isVoiceAssistantEnabled() else {
            guard operationIsCurrent(operation) else { return }
            state = .unavailable(.disabledByClinician)
            return
        }
        guard operationIsCurrent(operation) else { return }

        let permissions = transcriber.permissions
        guard permissions.areGranted else {
            state = .permissionRequired(permissions)
            return
        }

        await transitionToReadyIfAvailable(operation: operation)
    }

    /// Call only from an explicit press or pinch. This method is the sole path
    /// that can request permissions and open the microphone.
    func startPressToTalk() async {
        guard canBeginListening else { return }
        let operation = beginOperation()

        guard await enablementProvider.isVoiceAssistantEnabled() else {
            guard operationIsCurrent(operation) else { return }
            state = .unavailable(.disabledByClinician)
            return
        }
        guard operationIsCurrent(operation) else { return }

        var permissions = transcriber.permissions
        if !permissions.areGranted {
            state = .permissionRequired(permissions)
            permissions = await transcriber.requestPermissions()
            guard operationIsCurrent(operation) else { return }
        }
        guard permissions.areGranted else {
            state = .permissionRequired(permissions)
            return
        }

        let availability = await responder.availability()
        guard operationIsCurrent(operation) else { return }
        guard availability.isAvailable else {
            state = .unavailable(.appleIntelligence(availability))
            return
        }

        do {
            try transcriber.start(locale: locale)
            guard operationIsCurrent(operation) else {
                transcriber.cancel()
                return
            }
            state = .listening
        } catch let error as VoiceAssistantBackendError {
            switch error {
            case .recognizerUnavailable, .onDeviceRecognitionUnavailable:
                state = .unavailable(.speechRecognizerUnavailable)
            default:
                state = .failed(map(error))
            }
        } catch {
            state = .failed(map(error))
        }
    }

    /// Call when the explicit push-to-talk press or pinch ends.
    func stopPressToTalk() async {
        guard case .listening = state else { return }
        let operation = operationID
        state = .transcribing

        do {
            let rawTranscript = try await transcriber.stopAndReturnFinalTranscript()
            guard operationIsCurrent(operation) else { return }
            let transcript = rawTranscript.trimmingCharacters(
                in: .whitespacesAndNewlines
            )
            guard !transcript.isEmpty else {
                state = .failed(.emptyTranscript)
                return
            }

            state = .thinking
            let context = await contextProvider.voiceAssistantContext()
            guard operationIsCurrent(operation) else { return }
            let response = try await responder.respond(
                to: transcript,
                context: context
            )
            guard operationIsCurrent(operation) else { return }

            let spokenResponse = response.trimmingCharacters(
                in: .whitespacesAndNewlines
            )
            guard !spokenResponse.isEmpty else {
                state = .failed(.responseFailed(
                    "The assistant returned an empty answer. Try again."
                ))
                return
            }

            state = .speaking
            try await speaker.speak(spokenResponse, locale: locale)
            guard operationIsCurrent(operation) else { return }
            state = .ready
        } catch is CancellationError {
            guard operationIsCurrent(operation) else { return }
            state = .cancelled
        } catch {
            guard operationIsCurrent(operation) else { return }
            state = .failed(map(error))
        }
    }

    func cancel() {
        _ = beginOperation()
        transcriber.cancel()
        speaker.stop()
        state = .cancelled
    }

    func refreshClinicianEnablement() async {
        guard await enablementProvider.isVoiceAssistantEnabled() else {
            _ = beginOperation()
            transcriber.cancel()
            speaker.stop()
            state = .unavailable(.disabledByClinician)
            return
        }
        await prepare()
    }

    func resetAfterTerminalState() async {
        switch state {
        case .cancelled, .failed, .permissionRequired, .unavailable:
            await prepare()
        default:
            break
        }
    }

    private var canBeginListening: Bool {
        switch state {
        case .ready, .permissionRequired, .cancelled, .failed:
            true
        default:
            false
        }
    }

    private func transitionToReadyIfAvailable(operation: UUID) async {
        let availability = await responder.availability()
        guard operationIsCurrent(operation) else { return }
        state = availability.isAvailable
            ? .ready
            : .unavailable(.appleIntelligence(availability))
    }

    @discardableResult
    private func beginOperation() -> UUID {
        let identifier = UUID()
        operationID = identifier
        return identifier
    }

    private func operationIsCurrent(_ identifier: UUID) -> Bool {
        operationID == identifier
    }

    private func map(_ error: Error) -> VoiceAssistantFailure {
        guard let backendError = error as? VoiceAssistantBackendError else {
            return .responseFailed(
                "The voice assistant could not complete the request. Try again."
            )
        }
        switch backendError {
        case .recognizerUnavailable, .onDeviceRecognitionUnavailable:
            return .transcriptionFailed
        case .audioCapture:
            return .audioCaptureFailed
        case .noSpeech:
            return .emptyTranscript
        case .transcription:
            return .transcriptionFailed
        case let .questionRejected(message):
            return .questionRejected(message)
        case let .response(message):
            return .responseFailed(message)
        case .speechOutput:
            return .speechOutputFailed
        }
    }
}
