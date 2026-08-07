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
    var tintID: String
    var locked: Bool
    var sectionVisible: Bool
    var normalizedSlicePosition: Double
    var sectionOpacity: Double
    var selectedSliceIndex: Int
    var sliceCount: Int

    init(
        regionID: String?,
        x: Double,
        y: Double,
        z: Double,
        pitchDegrees: Double,
        yawDegrees: Double,
        rollDegrees: Double,
        scale: Double,
        opacity: Double,
        tintID: String,
        locked: Bool,
        sectionVisible: Bool,
        normalizedSlicePosition: Double,
        sectionOpacity: Double,
        selectedSliceIndex: Int,
        sliceCount: Int
    ) {
        self.regionID = regionID
        self.x = x
        self.y = y
        self.z = z
        self.pitchDegrees = pitchDegrees
        self.yawDegrees = yawDegrees
        self.rollDegrees = rollDegrees
        self.scale = scale
        self.opacity = opacity
        self.tintID = tintID
        self.locked = locked
        self.sectionVisible = sectionVisible
        self.normalizedSlicePosition = normalizedSlicePosition
        self.sectionOpacity = sectionOpacity
        self.selectedSliceIndex = selectedSliceIndex
        self.sliceCount = sliceCount
    }

    private enum CodingKeys: String, CodingKey {
        case regionID
        case x, y, z
        case pitchDegrees, yawDegrees, rollDegrees
        case scale, opacity, tintID, locked
        case sectionVisible, normalizedSlicePosition, sectionOpacity
        case selectedSliceIndex, sliceCount
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        regionID = try values.decodeIfPresent(String.self, forKey: .regionID)
        x = try values.decode(Double.self, forKey: .x)
        y = try values.decode(Double.self, forKey: .y)
        z = try values.decode(Double.self, forKey: .z)
        pitchDegrees = try values.decode(Double.self, forKey: .pitchDegrees)
        yawDegrees = try values.decode(Double.self, forKey: .yawDegrees)
        rollDegrees = try values.decode(Double.self, forKey: .rollDegrees)
        scale = try values.decode(Double.self, forKey: .scale)
        opacity = try values.decode(Double.self, forKey: .opacity)
        tintID = try values.decodeIfPresent(String.self, forKey: .tintID) ?? "cyan"
        locked = try values.decode(Bool.self, forKey: .locked)

        // Defaults keep v3 peers compatible with snapshots from the v2 prototype.
        sectionVisible = try values.decodeIfPresent(
            Bool.self,
            forKey: .sectionVisible
        ) ?? false
        normalizedSlicePosition = try values.decodeIfPresent(
            Double.self,
            forKey: .normalizedSlicePosition
        ) ?? 0.5
        sectionOpacity = try values.decodeIfPresent(
            Double.self,
            forKey: .sectionOpacity
        ) ?? 0.68
        selectedSliceIndex = try values.decodeIfPresent(
            Int.self,
            forKey: .selectedSliceIndex
        ) ?? 2
        sliceCount = try values.decodeIfPresent(
            Int.self,
            forKey: .sliceCount
        ) ?? 5
    }
}
