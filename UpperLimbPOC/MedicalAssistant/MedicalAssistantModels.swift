import Foundation

enum AssistantProvider: String, CaseIterable, Codable, Identifiable, Sendable {
    case onDevice
    case cloud

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .onDevice:
            "Apple Intelligence"
        case .cloud:
            "GPT-5.4 Cloud"
        }
    }

    var systemImage: String {
        switch self {
        case .onDevice:
            "cpu"
        case .cloud:
            "cloud.fill"
        }
    }
}

enum AssistantOnDeviceAvailability: Equatable, Sendable {
    case checking
    case available
    case requiresVisionOS26
    case deviceNotEligible
    case appleIntelligenceNotEnabled
    case modelNotReady
    case simulatorUnsupported
    case unsupportedLocale
    case unknown

    var isAvailable: Bool { self == .available }

    var label: String {
        switch self {
        case .checking:
            "Checking availability"
        case .available:
            "Available on this device"
        case .requiresVisionOS26:
            "Requires visionOS 26 or later"
        case .deviceNotEligible:
            "This device is not eligible"
        case .appleIntelligenceNotEnabled:
            "Apple Intelligence is not enabled"
        case .modelNotReady:
            "The on-device model is not ready"
        case .simulatorUnsupported:
            "Requires a physical Vision Pro"
        case .unsupportedLocale:
            "The current language is not supported"
        case .unknown:
            "Availability could not be determined"
        }
    }

    var userFacingMessage: String {
        switch self {
        case .simulatorUnsupported:
            "Apple Intelligence cannot generate responses in the Vision Pro Simulator. Select GPT-5.4 Cloud in Settings to test the assistant here, or run on a physical Vision Pro to use Apple Intelligence."
        case .modelNotReady:
            "Apple Intelligence is still preparing its local model. Finish the model download in Settings, then reopen the app."
        case .appleIntelligenceNotEnabled:
            "Turn on Apple Intelligence in the Vision Pro Settings app, then reopen the app."
        default:
            "Apple Intelligence is unavailable: \(label)."
        }
    }

    var configurationGuidance: String? {
        switch self {
        case .simulatorUnsupported:
            "The Vision Pro Simulator does not contain the Apple Intelligence model. Select GPT-5.4 Cloud to test chat here. To test the on-device model, select a physical Vision Pro as the Xcode destination."
        case .modelNotReady:
            "On a physical Vision Pro, keep Apple Intelligence enabled and connected to power and Wi-Fi until its local model download finishes."
        case .appleIntelligenceNotEnabled:
            "Enable Apple Intelligence in the Vision Pro Settings app before using the on-device provider."
        default:
            nil
        }
    }
}

enum AssistantAudience: String, CaseIterable, Codable, Identifiable, Sendable {
    case patient
    case clinician

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .patient:
            "Patient"
        case .clinician:
            "Clinician"
        }
    }
}

enum AssistantInputMode: String, CaseIterable, Identifiable {
    case voice
    case text

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .voice:
            "Voice"
        case .text:
            "Text"
        }
    }

    var systemImage: String {
        switch self {
        case .voice:
            "waveform"
        case .text:
            "keyboard"
        }
    }
}

enum AssistantMessageRole: String, Codable, Sendable {
    case user
    case assistant
}

struct AssistantCitation: Codable, Equatable, Identifiable, Sendable {
    let id: String
    let title: String
    let publisher: String
    let urlString: String?
    let lastVerified: String
    let reviewStatus: String

    var url: URL? {
        guard let urlString else { return nil }
        return URL(string: urlString)
    }
}

struct AssistantMessage: Codable, Equatable, Identifiable, Sendable {
    let id: UUID
    let role: AssistantMessageRole
    let text: String
    let createdAt: Date
    let citations: [AssistantCitation]
    let isLocalSafetyResponse: Bool

    init(
        id: UUID = UUID(),
        role: AssistantMessageRole,
        text: String,
        createdAt: Date = Date(),
        citations: [AssistantCitation] = [],
        isLocalSafetyResponse: Bool = false
    ) {
        self.id = id
        self.role = role
        self.text = text
        self.createdAt = createdAt
        self.citations = citations
        self.isLocalSafetyResponse = isLocalSafetyResponse
    }
}

struct AssistantAnatomyContext: Codable, Equatable, Sendable {
    let regionName: String
    let laterality: String
    let focusedStructure: String
    let educationalSource: String
}

struct AssistantConversationSnapshot: Codable, Equatable, Sendable {
    let audience: AssistantAudience
    let messages: [AssistantMessage]
}

enum AssistantActivity: Equatable {
    case idle
    case waitingForResponse

    var label: String {
        switch self {
        case .idle:
            "Ready"
        case .waitingForResponse:
            "Thinking"
        }
    }
}

enum AssistantWindowRoute: String, Codable, Hashable, Sendable {
    case primary
}

@MainActor
final class AssistantWindowCoordinator: ObservableObject {
    @Published private(set) var isAvatarPresented = false
    @Published private(set) var isConversationPresented = false
    private var didRequestAutomaticAvatarPresentation = false

    func claimAutomaticAvatarPresentation() -> Bool {
        guard !didRequestAutomaticAvatarPresentation else { return false }
        didRequestAutomaticAvatarPresentation = true
        return !isAvatarPresented
    }

    func avatarDidAppear() {
        isAvatarPresented = true
    }

    func avatarDidDisappear() {
        isAvatarPresented = false
    }

    func conversationDidAppear() {
        isConversationPresented = true
    }

    func conversationDidDisappear() {
        isConversationPresented = false
    }
}
