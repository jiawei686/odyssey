import Foundation

struct JointProbeRoute: Equatable, Sendable {
    private(set) var isPresented = false

    mutating func present() {
        isPresented = true
    }

    mutating func setPresented(_ value: Bool) {
        isPresented = value
    }
}
