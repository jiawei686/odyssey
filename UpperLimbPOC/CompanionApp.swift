import SwiftUI

@main
struct UpperLimbCompanionApp: App {
    @StateObject private var overlay = OverlayState()
    @StateObject private var peer = PeerSession(role: .host)

    var body: some Scene {
        WindowGroup {
            CompanionContentView()
                .environmentObject(overlay)
                .environmentObject(peer)
        }
    }
}

