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
            CompanionContentView()
                .environmentObject(overlay)
                .environmentObject(peer)
                .environmentObject(clinicianGuidance)
        }
    }
}
