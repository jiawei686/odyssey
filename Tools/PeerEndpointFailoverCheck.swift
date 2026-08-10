import Foundation

@main
enum PeerEndpointFailoverCheck {
    static func main() throws {
        try duplicateAndWrongFirstFailOverDeterministically()
        try removedActiveEndpointClearsStaleSelection()
        try exhaustedCandidatesRetryOnlyAfterReset()
        print("Peer endpoint failover checks passed")
    }

    private static func duplicateAndWrongFirstFailOverDeterministically() throws {
        var state = PeerEndpointFailoverState<String>()
        state.update(orderedEndpoints: ["wrong", "wrong", "clinician"])
        try require(state.orderedEndpoints == ["wrong", "clinician"],
                    "duplicate endpoints must be removed without reordering")
        try require(state.beginNextAttempt() == "wrong", "first candidate missing")
        state.failActiveAttempt()
        try require(state.beginNextAttempt() == "clinician",
                    "a rejected first peer must fail over to the clinician")
    }

    private static func removedActiveEndpointClearsStaleSelection() throws {
        var state = PeerEndpointFailoverState<String>()
        state.update(orderedEndpoints: ["stale", "live"])
        try require(state.beginNextAttempt() == "stale", "stale candidate missing")
        let removed = state.update(orderedEndpoints: ["live"])
        try require(removed, "removal must report an active stale endpoint")
        try require(state.activeEndpoint == nil, "removed endpoint remained active")
        try require(state.beginNextAttempt() == "live",
                    "live replacement must be immediately eligible")
    }

    private static func exhaustedCandidatesRetryOnlyAfterReset() throws {
        var state = PeerEndpointFailoverState<String>()
        state.update(orderedEndpoints: ["a", "b"])
        try require(state.beginNextAttempt() == "a", "candidate a missing")
        state.failActiveAttempt()
        try require(state.beginNextAttempt() == "b", "candidate b missing")
        state.failActiveAttempt()
        try require(state.beginNextAttempt() == nil,
                    "exhausted candidates must not spin immediately")
        state.resetAttempts()
        try require(state.beginNextAttempt() == "a",
                    "timed retry must restart deterministic ordering")
    }

    private static func require(
        _ condition: @autoclosure () -> Bool,
        _ message: String
    ) throws {
        guard condition() else { throw CheckError.failed(message) }
    }

    private enum CheckError: Error { case failed(String) }
}
