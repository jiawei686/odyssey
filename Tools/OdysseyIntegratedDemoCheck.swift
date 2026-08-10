import Foundation

@main
enum OdysseyIntegratedDemoCheck {
    static func main() throws {
        try defaultsFailClosed()
        try revealRequiresNegotiatedCapability()
        try pendingAndStaleDisableCommands()
        try lifecycleAlwaysReturnsToHome()
        try recoverableErrorFailsClosed()
        try referenceIdentityRemainsTruthful()
        print("Odyssey integrated-demo presentation checks passed")
    }

    private static func defaultsFailClosed() throws {
        let state = OdysseyExperienceViewState()
        try expect(!state.isSimulatedSession, "production default must not be simulated")
        try expect(!state.canSetReveal, "reveal must fail closed by default")
        try expect(!state.canSetAnatomyVisibility, "visibility must fail closed")
        try expect(!state.canMark, "marking must fail closed")
        try expect(state.wearerView == .unavailable, "live wearer view must remain unavailable")
    }

    private static func revealRequiresNegotiatedCapability() throws {
        var state = OdysseyExperienceViewState(
            phase: .activeSession,
            connection: .connected,
            supportsRevealControl: true
        )
        try expect(state.canSetReveal, "negotiated reveal should enable")
        try expect(!state.canSetAnatomyVisibility, "show/hide is not negotiated")
        try expect(!state.canMark, "projection/annotation is not negotiated")
        state.hasPendingAcknowledgment = true
        try expect(!state.canSetReveal, "single in-flight command must disable reveal")
    }

    private static func pendingAndStaleDisableCommands() throws {
        var state = OdysseyExperienceViewState(
            phase: .activeSession,
            connection: .stale,
            lastConfirmedAt: Date(timeIntervalSince1970: 1),
            supportsRevealControl: true
        )
        try expect(state.showsLastConfirmedOnly, "stale state must say last confirmed")
        try expect(!state.canSetReveal, "stale state must reject commands")
        state.connection = .connected
        state.hasPendingAcknowledgment = true
        try expect(!state.canSetReveal, "pending ACK must reject another command")
    }

    private static func lifecycleAlwaysReturnsToHome() throws {
        var avp = OdysseyExperienceViewState(phase: .home)
        try expect(avp.canStartExperience, "AVP Home must remain usable")
        avp.phase = .startingSession
        try expect(!avp.canStartExperience, "start transition must not be re-entrant")
        avp.phase = .activeSession
        try expect(avp.phase.isSessionOnScreen, "AVP session must be visible")
        avp.phase = .endingSession
        avp.phase = .home
        avp.canResumeSession = false
        try expect(avp.canStartExperience, "ending must restore AVP Home")

        var companion = OdysseyExperienceViewState(
            phase: .ready,
            connection: .connected
        )
        companion.phase = .activeSession
        try expect(companion.phase.isSessionOnScreen, "companion session must be visible")
        companion.phase = .endingSession
        companion.phase = .home
        companion.canResumeSession = false
        try expect(companion.canStartExperience, "ending must restore companion Home")
    }

    private static func recoverableErrorFailsClosed() throws {
        let state = OdysseyExperienceViewState(
            phase: .error,
            connection: .failed,
            recoverableError: OdysseyRecoverableError(message: "Transport unavailable"),
            supportsRevealControl: true,
            supportsMarking: true
        )
        try expect(!state.canSetReveal, "failed transport must reject reveal")
        try expect(!state.canMark, "failed transport must reject marking")
        try expect(state.canStartExperience, "AVP error must retain local recovery path")
    }

    private static func referenceIdentityRemainsTruthful() throws {
        let state = OdysseyExperienceViewState()
        try expect(state.patient.displayName == "Odyssey", "wrong demo identity")
        try expect(state.anatomy.displayName == "Right Forearm", "wrong model identity")
        try expect(
            OdysseyCopy.educationalDisclosure.contains("not patient imaging"),
            "reference-anatomy disclosure was weakened"
        )
    }

    private static func expect(_ condition: Bool, _ message: String) throws {
        guard condition else { throw CheckError.failed(message) }
    }

    private enum CheckError: Error { case failed(String) }
}
