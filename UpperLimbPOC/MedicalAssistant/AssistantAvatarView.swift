import RealityKit
import SwiftUI
import os

private let assistantAvatarLogger = Logger(
    subsystem: Bundle.main.bundleIdentifier ?? "UpperLimbPOC",
    category: "AssistantAvatar"
)

struct AssistantAvatarView: View {
    @EnvironmentObject private var windowCoordinator: AssistantWindowCoordinator
    @Environment(\.openWindow) private var openWindow
    @Environment(\.dismissWindow) private var dismissWindow
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var loadState: LoadState = .loading
    @State private var reloadID = UUID()
    @State private var accessibilityActivateSubscription: EventSubscription?
    @State private var idleMotionSubscription: EventSubscription?

    private static let maximumIdleYawDegrees: Float = 14
    private static let idleOscillationDuration: TimeInterval = 7

    private enum LoadState: Equatable {
        case loading
        case ready
        case failed
    }

    var body: some View {
        ZStack {
            RealityView { content in
                loadState = .loading
                accessibilityActivateSubscription?.cancel()
                idleMotionSubscription?.cancel()
                do {
                    guard let modelURL = Bundle.main.url(
                        forResource: "assistant-avatar",
                        withExtension: "usdz"
                    ) else {
                        throw CocoaError(.fileNoSuchFile)
                    }
                    let avatar = try await Entity(contentsOf: modelURL)
                    avatar.name = "MedicalAssistantAvatar"
                    content.add(avatar)
                    normalize(avatar)
                    configureInteraction(in: avatar)
                    accessibilityActivateSubscription = content.subscribe(
                        to: AccessibilityEvents.Activate.self
                    ) { event in
                        guard belongsToAvatar(event.entity) else { return }
                        Task { @MainActor in toggleConversation() }
                    }
                    startIdleMotion(for: avatar, in: content)
                    loadState = .ready
                } catch {
                    assistantAvatarLogger.error(
                        "Avatar load failed: \(error.localizedDescription, privacy: .public)"
                    )
                    loadState = .failed
                }
            }
            .id(reloadID)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .gesture(
                TapGesture()
                    .targetedToAnyEntity()
                    .onEnded { value in
                        guard belongsToAvatar(value.entity) else { return }
                        toggleConversation()
                    }
            )
            .accessibilityLabel("Medical education assistant")
            .accessibilityHint(
                windowCoordinator.isConversationPresented
                    ? "Activate to close the conversation"
                    : "Activate to open the conversation"
            )
            .accessibilityAddTraits(.isButton)
            .accessibilityAction {
                toggleConversation()
            }

            if loadState == .loading {
                ProgressView()
                    .controlSize(.large)
                    .accessibilityLabel("Loading assistant avatar")
            } else if loadState == .failed {
                VStack(spacing: 12) {
                    Label(
                        "Assistant model unavailable",
                        systemImage: "exclamationmark.triangle.fill"
                    )
                    .foregroundStyle(.orange)

                    Button("Retry", systemImage: "arrow.clockwise") {
                        reloadID = UUID()
                    }
                    .buttonStyle(.borderedProminent)
                }
                .padding(18)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear(perform: windowCoordinator.avatarDidAppear)
        .onChange(of: reduceMotion) {
            reloadID = UUID()
        }
        .onDisappear {
            accessibilityActivateSubscription?.cancel()
            accessibilityActivateSubscription = nil
            idleMotionSubscription?.cancel()
            idleMotionSubscription = nil
            windowCoordinator.avatarDidDisappear()
        }
    }

    private func toggleConversation() {
        if windowCoordinator.isConversationPresented {
            dismissWindow(id: "MedicalAssistant")
        } else {
            openWindow(
                id: "MedicalAssistant",
                value: AssistantWindowRoute.primary
            )
        }
    }

    private func normalize(_ avatar: Entity) {
        let bounds = avatar.visualBounds(relativeTo: nil)
        let height = max(bounds.extents.y, 0.001)
        let scale: Float = 0.42 / height
        avatar.scale = SIMD3<Float>(repeating: scale)
        avatar.position = -bounds.center * scale
    }

    private func startIdleMotion(
        for avatar: Entity,
        in content: some RealityViewContentProtocol
    ) {
        guard !reduceMotion else { return }

        let baseOrientation = avatar.orientation
        let maximumYaw = Self.maximumIdleYawDegrees * .pi / 180
        var elapsedTime: TimeInterval = 0
        idleMotionSubscription = content.subscribe(to: SceneEvents.Update.self) { event in
            elapsedTime += min(max(event.deltaTime, 0), 0.1)
            let phase = elapsedTime * 2 * Double.pi / Self.idleOscillationDuration
            let yaw = Float(sin(phase)) * maximumYaw
            let idleRotation = simd_quatf(
                angle: yaw,
                axis: SIMD3<Float>(0, 1, 0)
            )
            avatar.orientation = baseOrientation * idleRotation
        }
    }

    private func configureInteraction(in entity: Entity) {
        if entity.components[ModelComponent.self] != nil {
            entity.generateCollisionShapes(recursive: false)
            entity.components.set(InputTargetComponent())
            entity.components.set(HoverEffectComponent())

            var accessibility = AccessibilityComponent()
            accessibility.isAccessibilityElement = true
            accessibility.label = "Medical education assistant"
            accessibility.systemActions = [.activate]
            entity.components.set(accessibility)
        }

        for child in entity.children {
            configureInteraction(in: child)
        }
    }

    private func belongsToAvatar(_ entity: Entity) -> Bool {
        var candidate: Entity? = entity
        while let current = candidate {
            if current.name == "MedicalAssistantAvatar" { return true }
            candidate = current.parent
        }
        return false
    }
}
