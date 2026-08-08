import Foundation

@main
struct JointProbeRouteCheck {
    static func main() throws {
        var route = JointProbeRoute()
        try require(!route.isPresented, "joint probe should start hidden")

        route.present()
        try require(route.isPresented, "pinch activation should present the joint probe")

        route.setPresented(false)
        try require(!route.isPresented, "navigation dismissal should reset the route")

        print("Joint probe navigation route checks passed")
    }

    private static func require(_ condition: Bool, _ message: String) throws {
        guard condition else { throw RouteCheckFailure(message: message) }
    }
}

private struct RouteCheckFailure: Error {
    let message: String
}
