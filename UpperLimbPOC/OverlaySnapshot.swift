import Foundation

struct OverlaySnapshot: Codable, Equatable {
    var regionID: String?
    var x: Double
    var y: Double
    var z: Double
    var pitchDegrees: Double
    var yawDegrees: Double
    var rollDegrees: Double
    var scale: Double
    var opacity: Double
    var locked: Bool
}
