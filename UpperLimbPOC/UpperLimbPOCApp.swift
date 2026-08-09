import SwiftUI

@main
struct UpperLimbPOCApp: App {
    @StateObject private var overlay = OverlayState()
    @StateObject private var peer: PeerSession
    @StateObject private var clinicianGuidance: ClinicianGuidanceSession
    @StateObject private var tracking = LandmarkTrackingService()
    @StateObject private var medicalAssistant = MedicalAssistantStore()
    @StateObject private var assistantWindow = AssistantWindowCoordinator()
    @State private var immersionStyle: ImmersionStyle = .mixed
    @State private var probeImmersionStyle: ImmersionStyle = .mixed

    init() {
        let peer = PeerSession(role: .client)
        _peer = StateObject(wrappedValue: peer)
        _clinicianGuidance = StateObject(
            wrappedValue: ClinicianGuidanceSession(
                role: .visionPro,
                peer: peer,
                localDisplayName: "Apple Vision Pro"
            )
        )
    }

    var body: some Scene {
        WindowGroup(id: "AnatomyLibrary") {
            ContentView()
                .environmentObject(overlay)
                .environmentObject(peer)
                .environmentObject(clinicianGuidance)
                .environmentObject(tracking)
                .environmentObject(assistantWindow)
        }
        .defaultSize(width: 960, height: 720)

        WindowGroup(id: "TrackingStatus") {
            TrackingStatusView()
                .environmentObject(overlay)
                .environmentObject(peer)
                .environmentObject(clinicianGuidance)
                .environmentObject(tracking)
                .environmentObject(assistantWindow)
        }
        .defaultSize(width: 820, height: 620)
        .windowStyle(.plain)

        WindowGroup(id: "JointProbe") {
            JointProbeView()
                .environmentObject(tracking)
                .environmentObject(clinicianGuidance)
        }
        .defaultSize(width: 980, height: 760)
        .windowStyle(.plain)

        WindowGroup(id: "MedicalAssistant", for: AssistantWindowRoute.self) { _ in
            MedicalAssistantView()
                .environmentObject(medicalAssistant)
                .environmentObject(overlay)
                .environmentObject(assistantWindow)
        }
        .defaultSize(width: 620, height: 720)
        .windowStyle(.plain)

        ImmersiveSpace(id: "BoneOverlay") {
            ImmersiveView()
                .environmentObject(overlay)
                .environmentObject(peer)
                .environmentObject(clinicianGuidance)
                .environmentObject(tracking)
        }
        .immersionStyle(selection: $immersionStyle, in: .mixed)

        ImmersiveSpace(id: "JointProbeSpace") {
            JointProbeImmersiveView()
                .environmentObject(tracking)
                .environmentObject(clinicianGuidance)
        }
        .immersionStyle(selection: $probeImmersionStyle, in: .mixed)
    }
}
