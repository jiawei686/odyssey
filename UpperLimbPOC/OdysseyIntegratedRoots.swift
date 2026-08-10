#if DEBUG
import SwiftUI

#if os(visionOS)
struct OdysseyIntegratedAVPRoot: View {
    @EnvironmentObject private var coordinator: OdysseyAVPCoordinator
    @EnvironmentObject private var assistantWindow: AssistantWindowCoordinator
    @Environment(\.openImmersiveSpace) private var openImmersiveSpace
    @Environment(\.dismissImmersiveSpace) private var dismissImmersiveSpace
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Group {
            if coordinator.showsDiagnostics {
                VStack(spacing: 0) {
                    HStack {
                        Button("Return to Odyssey Home", systemImage: "chevron.left") {
                            coordinator.closeDiagnostics()
                        }
                        .buttonStyle(.bordered)
                        Spacer()
                        Text("Setup & Diagnostics · AnatomyTOOL USDZ")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(16)
                    Divider()
                    OnArmAnatomyView()
                }
            } else {
                OdysseyAVPShell(
                    state: coordinator.odysseyViewState,
                    actions: .forwarding(to: coordinator)
                )
            }
        }
        .onAppear {
            coordinator.configureLifecycle(
                openTwin: {
                    switch await openImmersiveSpace(id: "ClinicalTwinSpace") {
                    case .opened: true
                    case .userCancelled, .error: false
                    @unknown default: false
                    }
                },
                dismissImmersive: {
                    await dismissImmersiveSpace()
                },
                presentAssistant: {
                    openWindow(id: "MedicalAssistantAvatar")
                }
            )
            coordinator.connect()
        }
        .task {
            guard assistantWindow.claimAutomaticAvatarPresentation() else { return }
            openWindow(id: "MedicalAssistantAvatar")
        }
    }
}
#endif

#if os(iOS)
struct OdysseyIntegratedCompanionRoot: View {
    @EnvironmentObject private var coordinator: OdysseyCompanionCoordinator

    var body: some View {
        Group {
            if coordinator.showsDiagnostics {
                NavigationStack {
                    CompanionContentView()
                        .toolbar {
                            ToolbarItem(placement: .topBarLeading) {
                                Button("Odyssey", systemImage: "chevron.left") {
                                    coordinator.closeDiagnostics()
                                }
                            }
                        }
                }
            } else {
                OdysseyClinicianShell(
                    state: coordinator.odysseyViewState,
                    actions: .forwarding(to: coordinator)
                )
            }
        }
    }
}
#endif
#endif
