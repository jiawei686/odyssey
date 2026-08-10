import Foundation

/// Deterministic candidate bookkeeping for Bonjour endpoint failover.
/// Network.framework endpoints stay outside this type so its removal,
/// duplicate, and wrong-first behavior can be checked without networking.
struct PeerEndpointFailoverState<Endpoint: Hashable & Sendable>: Sendable {
    private(set) var orderedEndpoints: [Endpoint] = []
    private(set) var attemptedEndpoints: Set<Endpoint> = []
    private(set) var activeEndpoint: Endpoint?

    /// Replaces the live browser snapshot. Returns true when the active
    /// endpoint disappeared and its connection must be cancelled.
    @discardableResult
    mutating func update(orderedEndpoints candidates: [Endpoint]) -> Bool {
        var seen = Set<Endpoint>()
        orderedEndpoints = candidates.filter { seen.insert($0).inserted }
        let available = Set(orderedEndpoints)
        attemptedEndpoints.formIntersection(available)

        guard let activeEndpoint, !available.contains(activeEndpoint) else {
            return false
        }
        self.activeEndpoint = nil
        return true
    }

    mutating func beginNextAttempt() -> Endpoint? {
        guard activeEndpoint == nil else { return nil }
        guard let next = orderedEndpoints.first(where: {
            !attemptedEndpoints.contains($0)
        }) else { return nil }
        activeEndpoint = next
        return next
    }

    mutating func failActiveAttempt() {
        guard let activeEndpoint else { return }
        attemptedEndpoints.insert(activeEndpoint)
        self.activeEndpoint = nil
    }

    mutating func resetAttempts() {
        activeEndpoint = nil
        attemptedEndpoints.removeAll(keepingCapacity: true)
    }

    mutating func reset() {
        orderedEndpoints.removeAll(keepingCapacity: true)
        attemptedEndpoints.removeAll(keepingCapacity: true)
        activeEndpoint = nil
    }
}
