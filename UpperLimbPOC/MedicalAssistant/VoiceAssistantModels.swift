import Foundation

enum VoiceAssistantPermissionStatus: String, Equatable, Sendable {
    case undetermined
    case denied
    case restricted
    case granted
}

struct VoiceAssistantPermissions: Equatable, Sendable {
    let microphone: VoiceAssistantPermissionStatus
    let speechRecognition: VoiceAssistantPermissionStatus

    var areGranted: Bool {
        microphone == .granted && speechRecognition == .granted
    }
}

enum VoiceAssistantUnavailableReason: Equatable, Sendable {
    case notPrepared
    case disabledByClinician
    case appleIntelligence(AssistantOnDeviceAvailability)
    case speechRecognizerUnavailable

    var userFacingMessage: String {
        switch self {
        case .notPrepared:
            "Voice assistant is preparing."
        case .disabledByClinician:
            "Voice assistant is disabled by the clinician."
        case let .appleIntelligence(availability):
            availability.userFacingMessage
        case .speechRecognizerUnavailable:
            "On-device speech recognition is unavailable for the current language."
        }
    }
}

enum VoiceAssistantFailure: Equatable, Sendable {
    case permissionDenied
    case audioCaptureFailed
    case emptyTranscript
    case transcriptionFailed
    case questionRejected(String)
    case responseFailed(String)
    case speechOutputFailed

    var userFacingMessage: String {
        switch self {
        case .permissionDenied:
            "Microphone and Speech Recognition permission are required for push-to-talk."
        case .audioCaptureFailed:
            "The microphone could not start. Try push-to-talk again."
        case .emptyTranscript:
            "No question was heard. Press and hold, then speak clearly."
        case .transcriptionFailed:
            "The question could not be transcribed. Try again."
        case let .questionRejected(message), let .responseFailed(message):
            message
        case .speechOutputFailed:
            "The answer was prepared, but spoken playback failed."
        }
    }
}

enum VoiceAssistantState: Equatable, Sendable {
    case unavailable(VoiceAssistantUnavailableReason)
    case permissionRequired(VoiceAssistantPermissions)
    case ready
    case listening
    case transcribing
    case thinking
    case speaking
    case cancelled
    case failed(VoiceAssistantFailure)

    var label: String {
        switch self {
        case .unavailable:
            "Unavailable"
        case .permissionRequired:
            "Permission required"
        case .ready:
            "Ready"
        case .listening:
            "Listening"
        case .transcribing:
            "Transcribing"
        case .thinking:
            "Thinking"
        case .speaking:
            "Speaking"
        case .cancelled:
            "Cancelled"
        case .failed:
            "Try again"
        }
    }

    var userFacingMessage: String? {
        switch self {
        case let .unavailable(reason):
            reason.userFacingMessage
        case .permissionRequired:
            "Allow Microphone and Speech Recognition access. Audio and transcripts are not saved."
        case let .failed(failure):
            failure.userFacingMessage
        case .cancelled:
            "Voice assistant stopped."
        default:
            nil
        }
    }
}

enum VoiceAssistantRevealState: String, Equatable, Sendable {
    case surface
    case mixed
    case bone
}

struct VoiceAssistantContextSnapshot: Equatable, Sendable {
    let educationalCaseName: String
    let modelName: String
    let regionName: String
    let laterality: String
    let revealState: VoiceAssistantRevealState
    let focusedAnnotationLabel: String?
    let audience: AssistantAudience

    static let odysseyRightForearm = VoiceAssistantContextSnapshot(
        educationalCaseName: "Odyssey (Demo)",
        modelName: "Right Forearm VRT",
        regionName: "Right Forearm",
        laterality: "right",
        revealState: .surface,
        focusedAnnotationLabel: nil,
        audience: .patient
    )
}

@MainActor
protocol VoiceAssistantTranscribing: AnyObject {
    var permissions: VoiceAssistantPermissions { get }

    func requestPermissions() async -> VoiceAssistantPermissions
    func start(locale: Locale) throws
    func stopAndReturnFinalTranscript() async throws -> String
    func cancel()
}

@MainActor
protocol VoiceAssistantSpeaking: AnyObject {
    func speak(_ text: String, locale: Locale) async throws
    func stop()
}

protocol VoiceAssistantResponding: Sendable {
    func availability() async -> AssistantOnDeviceAvailability
    func respond(
        to transcript: String,
        context: VoiceAssistantContextSnapshot
    ) async throws -> String
}

protocol VoiceAssistantContextProviding: Sendable {
    func voiceAssistantContext() async -> VoiceAssistantContextSnapshot
}

protocol VoiceAssistantEnablementProviding: Sendable {
    func isVoiceAssistantEnabled() async -> Bool
}

struct StaticVoiceAssistantContextProvider: VoiceAssistantContextProviding {
    let context: VoiceAssistantContextSnapshot

    func voiceAssistantContext() async -> VoiceAssistantContextSnapshot {
        context
    }
}

struct StaticVoiceAssistantEnablementProvider: VoiceAssistantEnablementProviding {
    let isEnabled: Bool

    func isVoiceAssistantEnabled() async -> Bool {
        isEnabled
    }
}

enum VoiceAssistantBackendError: LocalizedError, Equatable, Sendable {
    case recognizerUnavailable
    case onDeviceRecognitionUnavailable
    case audioCapture
    case noSpeech
    case transcription
    case questionRejected(String)
    case response(String)
    case speechOutput

    var errorDescription: String? {
        switch self {
        case .recognizerUnavailable, .onDeviceRecognitionUnavailable:
            "On-device speech recognition is unavailable for the current language."
        case .audioCapture:
            VoiceAssistantFailure.audioCaptureFailed.userFacingMessage
        case .noSpeech:
            VoiceAssistantFailure.emptyTranscript.userFacingMessage
        case .transcription:
            VoiceAssistantFailure.transcriptionFailed.userFacingMessage
        case let .questionRejected(message), let .response(message):
            message
        case .speechOutput:
            VoiceAssistantFailure.speechOutputFailed.userFacingMessage
        }
    }
}
