import Foundation

// Claude-owned action adapter for the Odyssey session shell.
// Views express *intentions* only. They never open, dismiss or order windows,
// never touch PeerSession/ARKit/RealityKit, and never assume an intention
// succeeded — the coordinator republishes state and the views re-render.

/// Closure-based action surface handed to every Odyssey screen.
public struct OdysseyExperienceActions {
    public var connect: () -> Void
    public var retryConnection: () -> Void
    public var startSession: () -> Void
    public var resumeSession: () -> Void
    /// Requests teardown. The coordinator is responsible for stopping
    /// tracking, dismissing immersive content and restoring Home in the
    /// correct order; no frontend view calls dismissWindow.
    public var endSession: () -> Void
    public var returnHome: () -> Void
    public var openAssistant: () -> Void
    public var openDiagnostics: () -> Void
    public var setAnatomyVisible: (Bool) -> Void
    /// Sent once on interaction end, not continuously while dragging.
    public var setRevealAmount: (Double) -> Void
    public var markFracture: () -> Void
    public var undo: () -> Void
    public var clearGuidance: () -> Void

    public init(
        connect: @escaping () -> Void,
        retryConnection: @escaping () -> Void,
        startSession: @escaping () -> Void,
        resumeSession: @escaping () -> Void,
        endSession: @escaping () -> Void,
        returnHome: @escaping () -> Void,
        openAssistant: @escaping () -> Void,
        openDiagnostics: @escaping () -> Void,
        setAnatomyVisible: @escaping (Bool) -> Void,
        setRevealAmount: @escaping (Double) -> Void,
        markFracture: @escaping () -> Void,
        undo: @escaping () -> Void,
        clearGuidance: @escaping () -> Void
    ) {
        self.connect = connect
        self.retryConnection = retryConnection
        self.startSession = startSession
        self.resumeSession = resumeSession
        self.endSession = endSession
        self.returnHome = returnHome
        self.openAssistant = openAssistant
        self.openDiagnostics = openDiagnostics
        self.setAnatomyVisible = setAnatomyVisible
        self.setRevealAmount = setRevealAmount
        self.markFracture = markFracture
        self.undo = undo
        self.clearGuidance = clearGuidance
    }
}

/// The integration boundary. Codex's production lifecycle/session coordinator
/// conforms to this; the shell needs nothing else from the backend.
@MainActor
public protocol OdysseyExperienceControlling: AnyObject {
    var odysseyViewState: OdysseyExperienceViewState { get }

    func connect()
    func retryConnection()
    func startSession()
    func resumeSession()
    func endSession()
    func returnHome()
    func openAssistant()
    func openDiagnostics()
    func setAnatomyVisible(_ isVisible: Bool)
    func setRevealAmount(_ amount: Double)
    func markFracture()
    func undo()
    func clearGuidance()
}

public extension OdysseyExperienceActions {
    /// Single integration point: bind the shell to any controller.
    @MainActor
    static func forwarding(
        to controller: OdysseyExperienceControlling
    ) -> OdysseyExperienceActions {
        OdysseyExperienceActions(
            connect: { [weak controller] in controller?.connect() },
            retryConnection: { [weak controller] in controller?.retryConnection() },
            startSession: { [weak controller] in controller?.startSession() },
            resumeSession: { [weak controller] in controller?.resumeSession() },
            endSession: { [weak controller] in controller?.endSession() },
            returnHome: { [weak controller] in controller?.returnHome() },
            openAssistant: { [weak controller] in controller?.openAssistant() },
            openDiagnostics: { [weak controller] in controller?.openDiagnostics() },
            setAnatomyVisible: { [weak controller] in controller?.setAnatomyVisible($0) },
            setRevealAmount: { [weak controller] in controller?.setRevealAmount($0) },
            markFracture: { [weak controller] in controller?.markFracture() },
            undo: { [weak controller] in controller?.undo() },
            clearGuidance: { [weak controller] in controller?.clearGuidance() }
        )
    }

    /// No-op actions for static SwiftUI previews.
    static let inert = OdysseyExperienceActions(
        connect: {},
        retryConnection: {},
        startSession: {},
        resumeSession: {},
        endSession: {},
        returnHome: {},
        openAssistant: {},
        openDiagnostics: {},
        setAnatomyVisible: { _ in },
        setRevealAmount: { _ in },
        markFracture: {},
        undo: {},
        clearGuidance: {}
    )
}
