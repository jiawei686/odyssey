import SwiftUI

// Claude-owned shared presentation components for the Odyssey session shell.
// Value-and-closure only: no PeerSession, ARKit, RealityKit or tracking types.

// MARK: - Status rows

/// Connection status. Always symbol + text, never colour alone.
public struct OdysseyConnectionStatusRow: View {
    public let connection: OdysseyConnectionState
    public let peerDisplayName: String?
    public let isSimulatedSession: Bool
    public let lastConfirmedAt: Date?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    public init(
        connection: OdysseyConnectionState,
        peerDisplayName: String? = nil,
        isSimulatedSession: Bool = false,
        lastConfirmedAt: Date? = nil
    ) {
        self.connection = connection
        self.peerDisplayName = peerDisplayName
        self.isSimulatedSession = isSimulatedSession
        self.lastConfirmedAt = lastConfirmedAt
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 4) {
                    headline
                    if let peerDisplayName {
                        Text(peerDisplayName)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                HStack(spacing: 10) {
                    headline
                    if let peerDisplayName {
                        Text(peerDisplayName)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 0)
                    if showsSpinner {
                        ProgressView().controlSize(.small)
                    }
                }
            }

            if isSimulatedSession {
                Label(
                    "Simulated session — no Apple Vision Pro connected",
                    systemImage: "flask"
                )
                .font(.footnote)
                .foregroundStyle(.orange)
            }

            if let lastConfirmedAt {
                (Text("Last confirmed ")
                    + Text(lastConfirmedAt, style: .relative)
                    + Text(" ago"))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Connection")
        .accessibilityValue(accessibilityValue)
    }

    private var headline: some View {
        Label {
            Text(connection.displayTitle).font(.headline)
        } icon: {
            Image(systemName: connection.symbolName)
                .foregroundStyle(tint)
        }
    }

    private var showsSpinner: Bool {
        !reduceMotion && (connection == .connecting || connection == .searching)
    }

    private var tint: Color {
        switch connection {
        case .connected: .green
        case .stale: .orange
        case .failed: .red
        case .notConnected, .searching, .connecting: .secondary
        }
    }

    private var accessibilityValue: String {
        var parts = [connection.displayTitle]
        if let peerDisplayName { parts.append(peerDisplayName) }
        if isSimulatedSession {
            parts.append("Simulated session, no Apple Vision Pro connected")
        }
        if let lastConfirmedAt {
            let seconds = max(Int(Date().timeIntervalSince(lastConfirmedAt)), 0)
            parts.append("Last confirmed \(seconds) seconds ago")
        }
        return parts.joined(separator: ". ")
    }
}

/// Tracking health, in plain language for a patient.
public struct OdysseyTrackingStatusRow: View {
    public let tracking: OdysseyTrackingHealth

    public init(tracking: OdysseyTrackingHealth) {
        self.tracking = tracking
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Label {
                Text(tracking.displayTitle).font(.headline)
            } icon: {
                Image(systemName: tracking.symbolName)
                    .foregroundStyle(tint)
            }

            if let guidance = tracking.patientGuidance {
                Text(guidance)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Anatomy tracking")
        .accessibilityValue(
            [tracking.displayTitle, tracking.patientGuidance]
                .compactMap { $0 }
                .joined(separator: ". ")
        )
    }

    private var tint: Color {
        switch tracking {
        case .tracking: .green
        case .degraded: .orange
        case .lost: .red
        case .notStarted, .acquiring: .secondary
        }
    }
}

/// "Applying…" / "Up to date" indicator distinguishing desired from applied.
public struct OdysseyApplyingIndicator: View {
    public let isApplying: Bool
    public let showsLastConfirmedOnly: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init(isApplying: Bool, showsLastConfirmedOnly: Bool) {
        self.isApplying = isApplying
        self.showsLastConfirmedOnly = showsLastConfirmedOnly
    }

    public var body: some View {
        Group {
            if isApplying {
                HStack(spacing: 8) {
                    if reduceMotion {
                        Image(systemName: "hourglass")
                    } else {
                        ProgressView().controlSize(.small)
                    }
                    Text("Applying…")
                }
                .foregroundStyle(.secondary)
            } else if showsLastConfirmedOnly {
                Label("Last confirmed state", systemImage: "clock")
                    .foregroundStyle(.orange)
            } else {
                Label("Up to date", systemImage: "checkmark.circle")
                    .foregroundStyle(.secondary)
            }
        }
        .font(.subheadline)
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Identity cards

public struct OdysseyIdentityCard: View {
    public let title: String
    public let value: String
    public let detail: String?
    public let symbolName: String

    public init(title: String, value: String, detail: String?, symbolName: String) {
        self.title = title
        self.value = value
        self.detail = detail
        self.symbolName = symbolName
    }

    public var body: some View {
        HStack(spacing: 14) {
            Image(systemName: symbolName)
                .font(.title2)
                .foregroundStyle(.secondary)
                .frame(width: 32)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(value)
                    .font(.title3.weight(.semibold))
                if let detail {
                    Text(detail)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer(minLength: 0)
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(.regularMaterial)
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel(title)
        .accessibilityValue([value, detail].compactMap { $0 }.joined(separator: ". "))
    }
}

// MARK: - Reveal control

/// Bone-model opacity presented as a clinical visualisation control.
/// The value is sent once on release, never streamed while dragging.
public struct OdysseyRevealControl: View {
    public let desired: OdysseyRevealAmount
    public let applied: OdysseyRevealAmount
    public let isEnabled: Bool
    public let onCommit: (Double) -> Void

    @State private var draft: Double
    @State private var isEditing = false

    public init(
        desired: OdysseyRevealAmount,
        applied: OdysseyRevealAmount,
        isEnabled: Bool,
        onCommit: @escaping (Double) -> Void
    ) {
        self.desired = desired
        self.applied = applied
        self.isEnabled = isEnabled
        self.onCommit = onCommit
        _draft = State(initialValue: desired.value)
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Bone Model Visibility")
                .font(.headline)

            Slider(
                value: $draft,
                in: 0...1,
                label: {
                    Text("Bone model visibility")
                },
                minimumValueLabel: {
                    Text("Hidden").font(.caption2).foregroundStyle(.secondary)
                },
                maximumValueLabel: {
                    Text("Full").font(.caption2).foregroundStyle(.secondary)
                },
                onEditingChanged: { editing in
                    isEditing = editing
                    if !editing {
                        // One send per interaction, on release.
                        onCommit(draft)
                    }
                }
            )
            .disabled(!isEnabled)
            .accessibilityLabel("Bone model visibility")
            .accessibilityValue(accessibilityValue)

            HStack(spacing: 6) {
                Text("Showing \(OdysseyRevealAmount(clamping: draft).layerName)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                if applied != OdysseyRevealAmount(clamping: draft) {
                    Text("· confirmed \(applied.layerName)")
                        .font(.footnote)
                        .foregroundStyle(.orange)
                }
            }
            .accessibilityElement(children: .combine)
        }
        .onChange(of: desired) { _, newValue in
            guard !isEditing else { return }
            draft = newValue.value
        }
    }

    private var accessibilityValue: String {
        let current = OdysseyRevealAmount(clamping: draft)
        var text = "\(current.layerName), \(current.percentText)"
        if applied != current {
            text += ". Confirmed visibility \(applied.layerName)"
        }
        return text
    }
}

// MARK: - Reference anatomy viewer

/// Calm schematic of the reference forearm twin. Renders **applied** state
/// only, so an unacknowledged clinician intent is never drawn as placed.
/// Deliberately diagrammatic: no imagery implying diagnostic accuracy.
public struct OdysseyReferenceAnatomyView: View {
    public let reveal: OdysseyRevealAmount
    public let isAnatomyVisible: Bool
    public let markers: [OdysseyEducationalMarker]
    public let wearerView: OdysseyWearerViewAvailability
    public let showsLastConfirmedOnly: Bool

    public init(
        reveal: OdysseyRevealAmount,
        isAnatomyVisible: Bool,
        markers: [OdysseyEducationalMarker],
        wearerView: OdysseyWearerViewAvailability,
        showsLastConfirmedOnly: Bool
    ) {
        self.reveal = reveal
        self.isAnatomyVisible = isAnatomyVisible
        self.markers = markers
        self.wearerView = wearerView
        self.showsLastConfirmedOnly = showsLastConfirmedOnly
    }

    public var body: some View {
        VStack(spacing: 8) {
            ZStack {
                RoundedRectangle(cornerRadius: 16)
                    .fill(.thinMaterial)

                Canvas { context, size in
                    draw(in: context, size: size)
                }
                .padding(12)

                if !isAnatomyVisible {
                    Text("Anatomy hidden")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(.regularMaterial, in: Capsule())
                }
            }
            .overlay(alignment: .topLeading) {
                Label(OdysseyCopy.liveWearerViewUnavailable, systemImage: "video.slash")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(.regularMaterial, in: Capsule())
                    .padding(10)
            }
            .overlay(alignment: .topTrailing) {
                if showsLastConfirmedOnly {
                    Label("Last confirmed", systemImage: "clock")
                        .font(.caption2)
                        .foregroundStyle(.orange)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(.regularMaterial, in: Capsule())
                        .padding(10)
                }
            }

            Text(OdysseyCopy.referenceAnatomyNote)
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Reference anatomy")
        .accessibilityValue(accessibilityValue)
    }

    private func draw(in context: GraphicsContext, size: CGSize) {
        // Vertical inset clears the corner status badges.
        let rect = CGRect(origin: .zero, size: size)
            .insetBy(dx: size.width * 0.28, dy: 34)
        guard rect.width > 8, rect.height > 24 else { return }

        func band(_ inset: CGFloat, _ color: Color) {
            let r = rect.insetBy(dx: inset, dy: 0)
            guard r.width > 2 else { return }
            context.fill(
                Path(roundedRect: r, cornerRadius: r.width / 2),
                with: .color(color)
            )
        }

        guard isAnatomyVisible else {
            context.stroke(
                Path(roundedRect: rect, cornerRadius: rect.width / 2),
                with: .color(.secondary.opacity(0.4)),
                style: StrokeStyle(lineWidth: 1.5, dash: [5, 5])
            )
            return
        }

        let width = rect.width
        band(0, Color(red: 0.91, green: 0.76, blue: 0.66))
        if reveal.value >= 0.25 {
            band(width * 0.08, Color(red: 0.96, green: 0.87, blue: 0.55))
        }
        if reveal.value >= 0.55 {
            band(width * 0.17, Color(red: 0.78, green: 0.38, blue: 0.36))
        }
        if reveal.value >= 0.85 {
            let boneColor = Color(white: 0.94)
            let boneWidth = width * 0.17
            for offset in [-width * 0.13, width * 0.13] {
                let boneRect = CGRect(
                    x: rect.midX + offset - boneWidth / 2,
                    y: rect.minY + rect.height * 0.06,
                    width: boneWidth,
                    height: rect.height * 0.88
                )
                context.fill(
                    Path(roundedRect: boneRect, cornerRadius: boneWidth / 2),
                    with: .color(boneColor)
                )
            }
        }

        context.stroke(
            Path(roundedRect: rect, cornerRadius: rect.width / 2),
            with: .color(.secondary.opacity(0.5)),
            lineWidth: 1
        )

        // Applied markers only.
        for marker in markers {
            let y = rect.minY + rect.height * marker.normalizedPosition
            var ring = Path()
            ring.addEllipse(in: CGRect(x: rect.midX - 11, y: y - 11, width: 22, height: 22))
            context.stroke(ring, with: .color(.accentColor), lineWidth: 3)
            var dot = Path()
            dot.addEllipse(in: CGRect(x: rect.midX - 4, y: y - 4, width: 8, height: 8))
            context.fill(dot, with: .color(.accentColor))
        }
    }

    private var accessibilityValue: String {
        var parts: [String] = [OdysseyCopy.liveWearerViewUnavailable]
        parts.append(isAnatomyVisible ? "Anatomy visible" : "Anatomy hidden")
        if isAnatomyVisible {
            parts.append("Bone model visibility \(reveal.layerName)")
        }
        parts.append(
            markers.isEmpty
                ? "No educational markers"
                : "\(markers.count) educational marker\(markers.count == 1 ? "" : "s") placed"
        )
        if showsLastConfirmedOnly {
            parts.append("Showing the last confirmed state")
        }
        return parts.joined(separator: ". ")
    }
}

// MARK: - Disclosure

public struct OdysseyEducationalDisclosure: View {
    public init() {}

    public var body: some View {
        Text(OdysseyCopy.educationalDisclosure)
            .font(.footnote)
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.leading)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Error

public struct OdysseyErrorNotice: View {
    public let error: OdysseyRecoverableError
    public let retry: (() -> Void)?

    public init(error: OdysseyRecoverableError, retry: (() -> Void)?) {
        self.error = error
        self.retry = retry
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(error.message, systemImage: "exclamationmark.triangle.fill")
                .font(.subheadline)
                .foregroundStyle(.red)

            if let retry, error.isRetryable {
                Button("Try Again", action: retry)
                    .buttonStyle(.bordered)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 12).fill(.regularMaterial))
        .accessibilityElement(children: .contain)
    }
}
