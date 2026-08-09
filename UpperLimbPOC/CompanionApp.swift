import SwiftUI

@main
struct UpperLimbCompanionApp: App {
    @StateObject private var overlay = OverlayState()
    @StateObject private var peer: PeerSession
    @StateObject private var clinicianGuidance: ClinicianGuidanceSession

    init() {
        let peer = PeerSession(role: .host)
        _peer = StateObject(wrappedValue: peer)
        _clinicianGuidance = StateObject(
            wrappedValue: ClinicianGuidanceSession(
                role: .companion,
                peer: peer,
                localDisplayName: "Clinician Companion"
            )
        )
    }

    var body: some Scene {
        WindowGroup {
            Group {
#if DEBUG
                if CTForearmVRTFeatureGate.isEnabled {
                    CTForearmVRTPreview()
                } else if AnatomicalLayerUIFeatureGate.isEnabled {
                    AnatomicalLayerLabHost()
                } else {
                    CompanionContentView()
                }
#else
                CompanionContentView()
#endif
            }
            .environmentObject(overlay)
            .environmentObject(peer)
            .environmentObject(clinicianGuidance)
        }
    }
}

#if DEBUG
/// Lab-only root for Claude's minimal flow. Connection truth comes from the
/// production PeerSession; no synthetic frame or simulated connection is used.
/// The current backend has no live AVP view/annotation capability, so the
/// screen intentionally has no displayed frame and Mark remains disabled.
@MainActor
private struct AnatomicalLayerLabHost: View {
    @EnvironmentObject private var peer: PeerSession

    private var state: AnatomicalAnnotationViewState {
        AnatomicalAnnotationViewState(
            sessionStatus: sessionStatus,
            peerDisplayName: peer.isConnected ? "Apple Vision Pro (Bonjour)" : nil,
            isSimulatedSession: false,
            displayedFrame: nil,
            phase: .idle
        )
    }

    private var sessionStatus: AnatomicalSessionStatus {
        if peer.isConnected { return .connected }
        if peer.status == "Not started" || peer.status == "Stopped"
            || peer.status.hasPrefix("Host failed")
            || peer.status.hasPrefix("Could not start")
            || peer.status.hasPrefix("Connection failed")
            || peer.status.hasPrefix("Disconnected")
        {
            return .notConnected
        }
        return .connecting
    }

    var body: some View {
        NavigationStack {
            AnatomicalClinicianScreen(state: state, actions: .inert) {
                AnatomicalLayerAnnotationScreen(state: state, actions: .inert)
            }
        }
        .safeAreaInset(edge: .bottom) {
            HStack(spacing: 10) {
                Label(
                    "Transport: \(peer.status)",
                    systemImage: peer.isConnected ? "vision.pro" : "network"
                )
                Spacer(minLength: 8)
                Text("Live AVP view and mark transport unavailable")
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(.bar)
        }
        .onAppear(perform: peer.start)
    }
}
#endif
