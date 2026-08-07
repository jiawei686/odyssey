import Foundation
import simd

@main
@MainActor
struct OverlayStateLogicCheck {
    static func main() {
        let overlay = OverlayState()

        overlay.setSectionPosition(-0.4)
        expect(overlay.normalizedSlicePosition == 0, "section position lower clamp")
        expect(overlay.selectedSliceIndex == 0, "section index lower clamp")

        overlay.setSectionPosition(0.76)
        expect(overlay.selectedSliceIndex == 3, "nearest reference slice mapping")

        overlay.selectSlice(99)
        expect(overlay.selectedSliceIndex == 4, "slice index upper clamp")
        expect(overlay.normalizedSlicePosition == 1, "slice-to-position mapping")

        overlay.sectionVisible = false
        overlay.cycleImagingMode()
        expect(overlay.sectionVisible, "imaging mode cycle")

        overlay.tint = .magenta
        overlay.opacity = 0.55
        overlay.sectionOpacity = 0.42
        overlay.setSectionPosition(0.75)
        overlay.x = 0.32
        overlay.locked = true
        overlay.resetPlacement()
        expect(overlay.x == 0, "placement reset")
        expect(!overlay.locked, "placement reset unlocks calibration")
        expect(overlay.tint == .magenta, "placement reset preserves colour")
        expect(overlay.opacity == 0.55, "placement reset preserves opacity")
        expect(overlay.sectionVisible, "placement reset preserves imaging mode")
        expect(overlay.sectionOpacity == 0.42, "placement reset preserves slice opacity")

        overlay.captureManualPlacement(
            position: SIMD3<Float>(2, -2, -4),
            entityScale: SIMD3<Float>(2, 2, 2)
        )
        expect(overlay.x == 0.50, "manual x upper clamp")
        expect(overlay.y == -0.50, "manual y lower clamp")
        expect(overlay.z == -1.50, "manual z lower clamp")
        expect(overlay.scale == 1.50, "manual scale upper clamp")

        let hostileSnapshot = OverlaySnapshot(
            regionID: BodyRegion.rightUpperLimb.rawValue,
            x: 9,
            y: -9,
            z: 4,
            pitchDegrees: 900,
            yawDegrees: -900,
            rollDegrees: 500,
            scale: 8,
            opacity: -1,
            tintID: "unknown",
            locked: true,
            sectionVisible: true,
            normalizedSlicePosition: 4,
            sectionOpacity: 9,
            selectedSliceIndex: 99,
            sliceCount: 900
        )
        overlay.applyCalibration(hostileSnapshot)
        expect(overlay.x == 0.50 && overlay.y == -0.50, "peer position clamps")
        expect(overlay.z == -0.20, "peer depth clamp")
        expect(overlay.pitchDegrees == 180, "peer pitch clamp")
        expect(overlay.yawDegrees == -180, "peer yaw clamp")
        expect(overlay.rollDegrees == 180, "peer roll clamp")
        expect(overlay.scale == 1.50, "peer scale clamp")
        expect(overlay.opacity == 0.25, "peer opacity clamp")
        expect(overlay.tint == .cyan, "unknown tint fallback")
        expect(overlay.normalizedSlicePosition == 1, "peer section position clamp")
        expect(overlay.sectionOpacity == 1, "peer section opacity clamp")

        overlay.focusBone(entityName: "Radius_r")
        expect(overlay.focusedBoneName == "Radius", "radius semantic mapping")
        overlay.focusBone(entityName: "Capitate_r")
        expect(overlay.focusedBoneName == "Capitate", "carpal semantic mapping")

        print("Overlay state logic checks passed.")
    }

    private static func expect(
        _ condition: @autoclosure () -> Bool,
        _ message: String
    ) {
        guard condition() else {
            fatalError("Overlay state logic check failed: \(message)")
        }
    }
}
