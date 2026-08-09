import SwiftUI

// Claude-owned companion presentation surface.
// Registered in UpperLimbCompanion at the frozen contract checkpoint.

extension ClinicianGuidanceConnectionStatus {
    var displayTitle: String {
        switch self {
        case .disconnected: "Not Connected"
        case .connecting: "Connecting…"
        case .connected: "Connected"
        case .syncing: "Syncing…"
        case .stale: "Connection Stale"
        case .error: "Connection Error"
        }
    }

    var displaySymbol: String {
        switch self {
        case .disconnected: "wifi.slash"
        case .connecting: "arrow.triangle.2.circlepath"
        case .connected: "checkmark.circle.fill"
        case .syncing: "arrow.triangle.2.circlepath.circle"
        case .stale: "clock.badge.exclamationmark"
        case .error: "exclamationmark.triangle.fill"
        }
    }

    var displayColor: Color {
        switch self {
        case .disconnected, .connecting: .secondary
        case .connected: .green
        case .syncing: .blue
        case .stale: .orange
        case .error: .red
        }
    }

    var offersRetry: Bool {
        switch self {
        case .disconnected, .stale, .error: true
        case .connecting, .connected, .syncing: false
        }
    }
}

extension ClinicianGuidanceErrorPayload {
    var displayMessage: String {
        switch code {
        case .transportUnavailable:
            "The connection to Apple Vision Pro was lost."
        case .trackingUnavailable:
            "Vision Pro cannot track the forearm right now."
        case .mappingUnavailable:
            "Vision Pro cannot map guidance onto the forearm right now."
        case .staleMessage, .replayedMessage, .outOfOrderMessage:
            "An outdated command was ignored. Try the change again."
        case .unsupportedVersion, .unsupportedCapability:
            "The Vision Pro app version is incompatible with this companion."
        case .malformedMessage:
            "A message could not be read and was discarded."
        }
    }
}

/// Connection and synchronization headline for the clinician companion.
/// Communicates state with symbol + text, never color alone.
struct ClinicianConnectionStatusView: View {
    let status: ClinicianGuidanceConnectionStatus
    let peerDisplayName: String?
    let lastAcknowledgedAt: Date?
    let lastError: ClinicianGuidanceErrorPayload?
    let retry: (() -> Void)?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 12) {
                Image(systemName: status.displaySymbol)
                    .font(.title3)
                    .foregroundStyle(status.displayColor)
                    .frame(width: 28)

                VStack(alignment: .leading, spacing: 2) {
                    Text(status.displayTitle)
                        .font(.headline)
                    Text(subtitle)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 0)

                if showsActivityIndicator {
                    ProgressView()
                        .controlSize(.small)
                }
            }

            if let lastAcknowledgedAt {
                HStack(spacing: 6) {
                    Image(systemName: "checkmark.circle")
                        .foregroundStyle(.secondary)
                    (Text("Last change confirmed ")
                        + Text(lastAcknowledgedAt, style: .relative)
                        + Text(" ago"))
                }
                .font(.footnote)
                .foregroundStyle(.secondary)
            }

            if let lastError {
                Label(lastError.displayMessage, systemImage: "exclamationmark.triangle.fill")
                    .font(.footnote)
                    .foregroundStyle(.red)
            }

            if let retry, status.offersRetry {
                Button("Retry Connection", action: retry)
                    .buttonStyle(.bordered)
                    .controlSize(.small)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Vision Pro connection")
        .accessibilityValue(accessibilitySummary)
    }

    private var showsActivityIndicator: Bool {
        !reduceMotion && (status == .connecting || status == .syncing)
    }

    private var subtitle: String {
        let device = peerDisplayName ?? "Apple Vision Pro"
        switch status {
        case .disconnected:
            return "Searching for \(device)"
        case .connecting:
            return "Reaching \(device)"
        case .connected, .syncing, .stale, .error:
            if lastAcknowledgedAt != nil {
                return device
            }
            return "\(device) — no changes confirmed yet"
        }
    }

    private var accessibilitySummary: String {
        var parts = [status.displayTitle, subtitle]
        if let lastAcknowledgedAt {
            let interval = Int(Date().timeIntervalSince(lastAcknowledgedAt))
            parts.append("Last change confirmed \(max(interval, 0)) seconds ago")
        }
        if let lastError {
            parts.append(lastError.displayMessage)
        }
        return parts.joined(separator: ". ")
    }
}

#Preview("All states") {
    List {
        ForEach(
            [ClinicianGuidanceConnectionStatus.disconnected, .connecting,
             .connected, .syncing, .stale, .error],
            id: \.rawValue
        ) { status in
            ClinicianConnectionStatusView(
                status: status,
                peerDisplayName: "Apple Vision Pro",
                lastAcknowledgedAt: status == .disconnected
                    ? nil
                    : Date().addingTimeInterval(-9),
                lastError: status == .error
                    ? ClinicianGuidanceErrorPayload(
                        code: .transportUnavailable,
                        relatedMessageID: nil,
                        detail: "Preview transport loss"
                    )
                    : nil,
                retry: status.offersRetry ? {} : nil
            )
        }
    }
}
