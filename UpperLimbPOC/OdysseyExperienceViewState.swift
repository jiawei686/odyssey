import Foundation

// Claude-owned presentation state for the Odyssey session shell.
// Presentation only: no transport, tracking, RealityKit or ARKit types.
// The production lifecycle/session coordinator (Codex) publishes this value;
// views render it and never synthesise connection, tracking, projection or
// acknowledgment state of their own.

// MARK: - Phase

/// The single shared phase driving both the visionOS patient experience and
/// the iPhone/iPad clinician companion.
public enum OdysseySessionPhase: String, Equatable, Sendable, CaseIterable {
    case home
    case connecting
    case ready
    case startingSession
    case activeSession
    case endingSession
    case reconnecting
    case error

    /// True while a session is on screen for the patient.
    public var isSessionOnScreen: Bool {
        switch self {
        case .activeSession, .endingSession, .reconnecting: true
        case .home, .connecting, .ready, .startingSession, .error: false
        }
    }

    /// True while the shell is performing a transition the user should not
    /// be able to re-trigger.
    public var isTransitioning: Bool {
        switch self {
        case .connecting, .startingSession, .endingSession, .reconnecting: true
        case .home, .ready, .activeSession, .error: false
        }
    }
}

// MARK: - Connection

public enum OdysseyConnectionState: String, Equatable, Sendable {
    case notConnected
    case searching
    case connecting
    case connected
    case stale
    case failed

    public var displayTitle: String {
        switch self {
        case .notConnected: "Not Connected"
        case .searching: "Searching…"
        case .connecting: "Connecting…"
        case .connected: "Connected"
        case .stale: "Connection Stale"
        case .failed: "Connection Failed"
        }
    }

    /// Symbol paired with text everywhere; status is never colour-only.
    public var symbolName: String {
        switch self {
        case .notConnected: "wifi.slash"
        case .searching: "dot.radiowaves.left.and.right"
        case .connecting: "arrow.triangle.2.circlepath"
        case .connected: "checkmark.circle.fill"
        case .stale: "clock.badge.exclamationmark"
        case .failed: "exclamationmark.triangle.fill"
        }
    }

    public var offersRetry: Bool {
        switch self {
        case .notConnected, .stale, .failed: true
        case .searching, .connecting, .connected: false
        }
    }

    public var isUsable: Bool { self == .connected }
}

// MARK: - Tracking

public enum OdysseyTrackingHealth: String, Equatable, Sendable {
    case notStarted
    case acquiring
    case tracking
    case degraded
    case lost

    public var displayTitle: String {
        switch self {
        case .notStarted: "Not Started"
        case .acquiring: "Finding Arm…"
        case .tracking: "Arm Tracked"
        case .degraded: "Tracking Reduced"
        case .lost: "Arm Not Visible"
        }
    }

    public var symbolName: String {
        switch self {
        case .notStarted: "hand.raised.slash"
        case .acquiring: "dot.viewfinder"
        case .tracking: "checkmark.circle.fill"
        case .degraded: "exclamationmark.circle"
        case .lost: "eye.slash"
        }
    }

    /// Patient-facing guidance, plain language, no technical vocabulary.
    public var patientGuidance: String? {
        switch self {
        case .notStarted: nil
        case .acquiring: "Hold your right forearm comfortably in view."
        case .tracking: nil
        case .degraded: "Move your arm a little closer for a steadier view."
        case .lost: "Bring your right forearm back into view."
        }
    }
}

// MARK: - Identity

public struct OdysseyPatientDescriptor: Equatable, Sendable {
    public let displayName: String
    public let detail: String?

    public init(displayName: String, detail: String? = nil) {
        self.displayName = displayName
        self.detail = detail
    }

    public static let odyssey = Self(
        displayName: "Odyssey",
        detail: "Demonstration participant"
    )
}

public struct OdysseyAnatomyDescriptor: Equatable, Sendable {
    public let displayName: String
    public let detail: String?

    public init(displayName: String, detail: String? = nil) {
        self.displayName = displayName
        self.detail = detail
    }

    public static let rightForearm = Self(
        displayName: "Right Forearm",
        detail: "Reference anatomical twin"
    )
}

// MARK: - Reveal

/// Normalised bone-model opacity. 0 = hidden, 1 = fully visible.
public struct OdysseyRevealAmount: Equatable, Sendable, Comparable {
    public let value: Double

    public init(clamping value: Double) {
        self.value = value.isFinite ? min(max(value, 0), 1) : 0
    }

    public static let surface = Self(clamping: 0)
    public static let bone = Self(clamping: 1)

    public static func < (lhs: Self, rhs: Self) -> Bool { lhs.value < rhs.value }

    /// Bone visibility name used for labels and VoiceOver values.
    public var layerName: String {
        value <= 0.005 ? "Hidden" : "Bone \(percentText)"
    }

    public var percentText: String {
        "\(Int((value * 100).rounded()))%"
    }
}

// MARK: - Markers

/// An educational marker confirmed by the headset. Frontend renders applied
/// markers only; clinician intent that has not been acknowledged is shown as
/// pending, never drawn as placed.
public struct OdysseyEducationalMarker: Equatable, Sendable, Identifiable {
    public let id: UUID
    /// Position along the forearm axis, 0 = elbow, 1 = wrist.
    public let normalizedPosition: Double
    public let label: String

    public init(
        id: UUID = UUID(),
        normalizedPosition: Double,
        label: String = "Educational marker"
    ) {
        self.id = id
        self.normalizedPosition = min(max(normalizedPosition, 0), 1)
        self.label = label
    }
}

// MARK: - Wearer view

/// Truthful description of the shared viewer area. The live wearer transport
/// does not exist yet; `.unavailable` is the only honest production value.
public enum OdysseyWearerViewAvailability: Equatable, Sendable {
    case unavailable
    case referenceAnatomyOnly

    public var isLiveWearerViewAvailable: Bool { false }

    public var placeholderTitle: String {
        switch self {
        case .unavailable, .referenceAnatomyOnly:
            "Live wearer view unavailable"
        }
    }
}

// MARK: - Assistant

public enum OdysseyAssistantAvailability: Equatable, Sendable {
    case unavailable
    case available

    public var isAvailable: Bool { self == .available }
}

// MARK: - Error

public struct OdysseyRecoverableError: Equatable, Sendable {
    public let message: String
    public let isRetryable: Bool

    public init(message: String, isRetryable: Bool = true) {
        self.message = message
        self.isRetryable = isRetryable
    }
}

// MARK: - View state

/// Everything the Odyssey shell renders. Every field is supplied by the
/// production coordinator; nothing here is inferred by a view.
public struct OdysseyExperienceViewState: Equatable, Sendable {
    public var phase: OdysseySessionPhase
    public var patient: OdysseyPatientDescriptor
    public var anatomy: OdysseyAnatomyDescriptor

    public var connection: OdysseyConnectionState
    public var peerDisplayName: String?
    /// True when this build is driven by a frontend mock rather than a device.
    public var isSimulatedSession: Bool

    public var trackingHealth: OdysseyTrackingHealth

    /// Confirmed by the headset.
    public var appliedAnatomyVisible: Bool
    /// Requested by the clinician.
    public var desiredAnatomyVisible: Bool
    public var appliedReveal: OdysseyRevealAmount
    public var desiredReveal: OdysseyRevealAmount
    public var appliedMarkers: [OdysseyEducationalMarker]

    public var hasPendingAcknowledgment: Bool
    public var lastConfirmedAt: Date?

    public var assistantAvailability: OdysseyAssistantAvailability
    public var wearerView: OdysseyWearerViewAvailability
    public var recoverableError: OdysseyRecoverableError?
    public var canResumeSession: Bool
    /// Capability truth supplied by the production coordinator. These remain
    /// false unless the connected AVP has negotiated and can apply them.
    public var supportsAnatomyVisibilityControl: Bool
    public var supportsRevealControl: Bool
    public var supportsMarking: Bool

    public init(
        phase: OdysseySessionPhase = .home,
        patient: OdysseyPatientDescriptor = .odyssey,
        anatomy: OdysseyAnatomyDescriptor = .rightForearm,
        connection: OdysseyConnectionState = .notConnected,
        peerDisplayName: String? = nil,
        isSimulatedSession: Bool = false,
        trackingHealth: OdysseyTrackingHealth = .notStarted,
        appliedAnatomyVisible: Bool = false,
        desiredAnatomyVisible: Bool = false,
        appliedReveal: OdysseyRevealAmount = .bone,
        desiredReveal: OdysseyRevealAmount = .bone,
        appliedMarkers: [OdysseyEducationalMarker] = [],
        hasPendingAcknowledgment: Bool = false,
        lastConfirmedAt: Date? = nil,
        assistantAvailability: OdysseyAssistantAvailability = .unavailable,
        wearerView: OdysseyWearerViewAvailability = .unavailable,
        recoverableError: OdysseyRecoverableError? = nil,
        canResumeSession: Bool = false,
        supportsAnatomyVisibilityControl: Bool = false,
        supportsRevealControl: Bool = false,
        supportsMarking: Bool = false
    ) {
        self.phase = phase
        self.patient = patient
        self.anatomy = anatomy
        self.connection = connection
        self.peerDisplayName = peerDisplayName
        self.isSimulatedSession = isSimulatedSession
        self.trackingHealth = trackingHealth
        self.appliedAnatomyVisible = appliedAnatomyVisible
        self.desiredAnatomyVisible = desiredAnatomyVisible
        self.appliedReveal = appliedReveal
        self.desiredReveal = desiredReveal
        self.appliedMarkers = appliedMarkers
        self.hasPendingAcknowledgment = hasPendingAcknowledgment
        self.lastConfirmedAt = lastConfirmedAt
        self.assistantAvailability = assistantAvailability
        self.wearerView = wearerView
        self.recoverableError = recoverableError
        self.canResumeSession = canResumeSession
        self.supportsAnatomyVisibilityControl = supportsAnatomyVisibilityControl
        self.supportsRevealControl = supportsRevealControl
        self.supportsMarking = supportsMarking
    }

    // MARK: Derived presentation rules

    /// Desired and applied differ, or a command is in flight.
    public var isApplying: Bool {
        hasPendingAcknowledgment
            || desiredAnatomyVisible != appliedAnatomyVisible
            || desiredReveal != appliedReveal
    }

    /// The displayed anatomy is the last confirmed state rather than a live one.
    public var showsLastConfirmedOnly: Bool {
        switch connection {
        case .stale, .failed, .notConnected: appliedMarkers.isEmpty == false || lastConfirmedAt != nil
        case .searching, .connecting, .connected: false
        }
    }

    /// New guidance may be sent. Stale, failed, disconnected and in-flight
    /// states all withhold it.
    public var canSendGuidance: Bool {
        connection.isUsable
            && phase == .activeSession
            && !hasPendingAcknowledgment
    }

    public var canSetAnatomyVisibility: Bool {
        canSendGuidance && supportsAnatomyVisibilityControl
    }

    public var canSetReveal: Bool {
        canSendGuidance && supportsRevealControl
    }

    public var canMark: Bool {
        canSendGuidance && supportsMarking
    }

    /// The patient may begin a local demonstration even with no clinician
    /// device, so the headset is never a dead end.
    public var canStartExperience: Bool {
        switch phase {
        case .home, .ready, .error: true
        case .connecting, .startingSession, .activeSession, .endingSession, .reconnecting: false
        }
    }

    public var isClinicianGuided: Bool {
        connection.isUsable
    }

    public var canUndo: Bool {
        canMark && !appliedMarkers.isEmpty
    }

    public var canClearGuidance: Bool {
        canMark && !appliedMarkers.isEmpty
    }

    /// Patient-facing summary of what the clinician is doing.
    public var clinicianGuidanceSummary: String {
        guard isClinicianGuided else {
            return "Self-guided demonstration"
        }
        if hasPendingAcknowledgment {
            return "Your clinician is updating the view…"
        }
        return "Guided by your clinician"
    }
}

// MARK: - Shared copy

public enum OdysseyCopy {
    public static let appTitle = "Odyssey Clinical Education"
    public static let educationalDisclosure =
        "Educational prototype — reference anatomy, not patient imaging and not for diagnosis."
    public static let referenceAnatomyNote =
        "Shared reference anatomy — not a live view of the wearer."
    public static let liveWearerViewUnavailable = "Live wearer view unavailable"
}
