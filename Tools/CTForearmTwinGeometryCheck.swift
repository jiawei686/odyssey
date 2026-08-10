import Foundation
import simd

@main
enum CTForearmTwinGeometryCheck {
    static func main() throws {
        try syntheticVolumeProducesOneShellAndTwoBones()
        if CommandLine.arguments.count == 2 {
            try bundledReferenceProducesRenderableGeometry(
                projectRoot: CommandLine.arguments[1]
            )
        }
        print("CT forearm twin geometry checks passed")
    }

    private static func syntheticVolumeProducesOneShellAndTwoBones() throws {
        let dimensions = SIMD3<Int>(14, 14, 9)
        var bytes = Data(repeating: 0, count: dimensions.x * dimensions.y * dimensions.z)
        for z in 0 ..< dimensions.z {
            for y in 0 ..< dimensions.y {
                for x in 0 ..< dimensions.x {
                    let dx = Float(x) - 6.5
                    let dy = Float(y) - 6.5
                    let radial = sqrt(dx * dx + dy * dy)
                    let value: UInt8
                    if radial <= 5.2 {
                        let boneA = hypot(dx + 2.1, dy) <= 1.25
                        let boneB = hypot(dx - 2.1, dy) <= 1.15
                        value = boneA || boneB ? 220 : 125
                    } else {
                        value = 0
                    }
                    bytes[index(x: x, y: y, z: z, dimensions: dimensions)] = value
                }
            }
        }

        let volume = try CTForearmVolumeData(bytes: bytes, dimensions: dimensions)
        let result = try CTForearmTwinGeometryBuilder.build(
            volume: volume,
            spacingMetres: SIMD3<Float>(0.001, 0.001, 0.003)
        )
        try expect(result.softTissue.triangleCount > 0, "soft-tissue shell missing")
        try expect(result.pairedBoneA.triangleCount > 0, "first bone missing")
        try expect(result.pairedBoneB.triangleCount > 0, "second bone missing")
        try expect(result.softTissue.sourceVoxelCount > result.pairedBoneA.sourceVoxelCount, "shell component selection failed")
        try expect(result.rendererRoute == .ctDerivedMeshFallback, "route must not claim spatial VRT")
    }

    private static func bundledReferenceProducesRenderableGeometry(
        projectRoot: String
    ) throws {
        let asset = URL(fileURLWithPath: projectRoot)
            .appendingPathComponent("UpperLimbPOC/CTVolume")
            .appendingPathComponent("visible-human-male-forearm-1680-1740.r8")
        let volume = try CTForearmVolumeData(bytes: Data(contentsOf: asset))
        let start = ContinuousClock.now
        let result = try CTForearmTwinGeometryBuilder.build(
            volume: volume,
            spacingMetres: CTForearmVolumeAsset.spacingMetres
        )
        let elapsed = start.duration(to: .now)
        try expect(result.softTissue.triangleCount >= 1_000, "reference shell is unexpectedly sparse")
        try expect(result.pairedBoneA.triangleCount >= 200, "reference bone A is unexpectedly sparse")
        try expect(result.pairedBoneB.triangleCount >= 200, "reference bone B is unexpectedly sparse")
        try expect(result.softTissue.longitudinalExtent == 1, "mesh longitudinal extent must be normalized for tracked scaling")
        print(
            "Reference mesh: soft=\(result.softTissue.triangleCount) triangles "
                + "boneA=\(result.pairedBoneA.triangleCount) "
                + "boneB=\(result.pairedBoneB.triangleCount) "
                + "build=\(elapsed)"
        )
    }

    private static func index(
        x: Int,
        y: Int,
        z: Int,
        dimensions: SIMD3<Int>
    ) -> Int {
        z * dimensions.x * dimensions.y + y * dimensions.x + x
    }

    private static func expect(
        _ condition: @autoclosure () -> Bool,
        _ message: String
    ) throws {
        guard condition() else { throw CheckError.failed(message) }
    }

    private enum CheckError: Error {
        case failed(String)
    }
}
