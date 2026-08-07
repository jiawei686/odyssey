import Foundation

@main
enum SnapshotCompatibilityCheck {
    static func main() throws {
        let legacySnapshot = """
        {
          "regionID": "rightUpperLimb",
          "x": 0.1,
          "y": -0.2,
          "z": -0.7,
          "pitchDegrees": -90,
          "yawDegrees": 5,
          "rollDegrees": 0,
          "scale": 1,
          "opacity": 0.7,
          "locked": true
        }
        """.data(using: .utf8)!

        let decoder = JSONDecoder()
        let decodedLegacy = try decoder.decode(
            OverlaySnapshot.self,
            from: legacySnapshot
        )
        precondition(decodedLegacy.sectionVisible == false)
        precondition(decodedLegacy.normalizedSlicePosition == 0.5)
        precondition(decodedLegacy.sectionOpacity == 0.68)
        precondition(decodedLegacy.selectedSliceIndex == 2)
        precondition(decodedLegacy.sliceCount == 5)
        precondition(decodedLegacy.tintID == "cyan")

        let current = OverlaySnapshot(
            regionID: "leftUpperLimb",
            x: 0,
            y: -0.15,
            z: -0.7,
            pitchDegrees: -90,
            yawDegrees: 0,
            rollDegrees: 0,
            scale: 1,
            opacity: 0.7,
            tintID: "amber",
            locked: false,
            sectionVisible: true,
            normalizedSlicePosition: 0.75,
            sectionOpacity: 0.55,
            selectedSliceIndex: 3,
            sliceCount: 5
        )
        let encoded = try JSONEncoder().encode(current)
        let roundTrip = try decoder.decode(OverlaySnapshot.self, from: encoded)
        precondition(roundTrip == current)

        print("Snapshot compatibility passed.")
    }
}
