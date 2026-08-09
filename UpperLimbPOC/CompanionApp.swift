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
