import SwiftUI

@main
struct UpperLimbPOCApp: App {
    @StateObject private var overlay = OverlayState()
    @StateObject private var peer = PeerSession(role: .client)
    @StateObject private var tracking = LandmarkTrackingService()
    @State private var immersionStyle: ImmersionStyle = .mixed

    var body: some Scene {
        WindowGroup(id: "AnatomyLibrary") {
            ContentView()
                .environmentObject(overlay)
                .environmentObject(peer)
        }
        .defaultSize(width: 960, height: 720)

        WindowGroup(id: "TrackingStatus") {
            TrackingStatusView()
                .environmentObject(overlay)
                .environmentObject(tracking)
        }
        .defaultSize(width: 560, height: 190)
        .windowStyle(.plain)

        ImmersiveSpace(id: "BoneOverlay") {
            ImmersiveView()
                .environmentObject(overlay)
                .environmentObject(peer)
                .environmentObject(tracking)
                .persistentSystemOverlays(.hidden)
        }
        .immersionStyle(selection: $immersionStyle, in: .mixed)
    }
}
