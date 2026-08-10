import SwiftUI

@main
struct UpperLimbPOCApp: App {
    @StateObject private var overlay = OverlayState()
    @StateObject private var peer: PeerSession
    @StateObject private var clinicianGuidance: ClinicianGuidanceSession
    @StateObject private var tracking: LandmarkTrackingService
    @StateObject private var medicalAssistant = MedicalAssistantStore()
    @StateObject private var assistantWindow = AssistantWindowCoordinator()
#if DEBUG
    @StateObject private var clinicalTwin: ClinicalTwinLabState
    @StateObject private var onArmAnatomy = OnArmAnatomyLabState()
    @StateObject private var odysseySession: OdysseyClinicalSessionService
    @StateObject private var odysseyCoordinator: OdysseyAVPCoordinator
#endif
    @State private var immersionStyle: ImmersionStyle = .mixed
    @State private var probeImmersionStyle: ImmersionStyle = .mixed
#if DEBUG
    @State private var clinicalTwinImmersionStyle: ImmersionStyle = .mixed
    @State private var onArmNormalImmersionStyle: ImmersionStyle = .mixed
    @State private var onArmSeeThroughImmersionStyle: ImmersionStyle = .mixed
#endif

    init() {
        let peer = PeerSession(role: .client)
        let tracking = LandmarkTrackingService()
        _peer = StateObject(wrappedValue: peer)
        _tracking = StateObject(wrappedValue: tracking)
        _clinicianGuidance = StateObject(
            wrappedValue: ClinicianGuidanceSession(
                role: .visionPro,
                peer: peer,
                localDisplayName: "Apple Vision Pro"
            )
        )
#if DEBUG
        let clinicalTwin = ClinicalTwinLabState()
        let odysseySession = OdysseyClinicalSessionService(
            role: .visionPro,
            peer: peer,
            localDisplayName: "Apple Vision Pro"
        )
        _clinicalTwin = StateObject(wrappedValue: clinicalTwin)
        _odysseySession = StateObject(wrappedValue: odysseySession)
        _odysseyCoordinator = StateObject(
            wrappedValue: OdysseyAVPCoordinator(
                peer: peer,
                session: odysseySession,
                tracking: tracking,
                clinicalTwin: clinicalTwin
            )
        )
#endif
    }

    var body: some Scene {
        WindowGroup(id: "AnatomyLibrary") {
            Group {
#if DEBUG
                if OdysseyIntegratedDemoFeatureGate.isEnabled {
                    OdysseyIntegratedAVPRoot()
                } else if OnArmAnatomyFeatureGate.isEnabled {
                    OnArmAnatomyView()
                } else if ClinicalTwinLabFeatureGate.isEnabled {
                    ClinicalTwinView()
                } else {
                    ContentView()
                }
#else
                ContentView()
#endif
            }
                .environmentObject(overlay)
                .environmentObject(peer)
                .environmentObject(clinicianGuidance)
                .environmentObject(tracking)
                .environmentObject(assistantWindow)
#if DEBUG
                .environmentObject(clinicalTwin)
                .environmentObject(onArmAnatomy)
                .environmentObject(odysseySession)
                .environmentObject(odysseyCoordinator)
#endif
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

#if DEBUG
        ImmersiveSpace(id: "ClinicalTwinSpace") {
            ClinicalTwinImmersiveView()
                .environmentObject(tracking)
                .environmentObject(clinicalTwin)
        }
        .immersionStyle(selection: $clinicalTwinImmersionStyle, in: .mixed)

        ImmersiveSpace(id: "OnArmAnatomyNormalSpace") {
            OnArmAnatomyImmersiveView()
                .environmentObject(tracking)
                .environmentObject(onArmAnatomy)
        }
        .upperLimbVisibility(.visible)
        .immersionStyle(selection: $onArmNormalImmersionStyle, in: .mixed)

        ImmersiveSpace(id: "OnArmAnatomySeeThroughSpace") {
            OnArmAnatomyImmersiveView()
                .environmentObject(tracking)
                .environmentObject(onArmAnatomy)
        }
        .upperLimbVisibility(.hidden)
        .immersionStyle(selection: $onArmSeeThroughImmersionStyle, in: .mixed)
#endif
    }
}
