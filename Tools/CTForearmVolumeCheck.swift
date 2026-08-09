import CryptoKit
import Foundation
import simd

@main
enum CTForearmVolumeCheck {
    static func main() throws {
        try checkMetadata()
        try checkSurfaceDepthAbstraction()
        try checkInvalidDataFailsClosed()
        if CommandLine.arguments.count == 2 {
            try checkBuiltAsset(projectRoot: CommandLine.arguments[1])
        }
        print("CT forearm volume checks passed")
    }

    private static func checkMetadata() throws {
        try expect(CTForearmVolumeAsset.dimensions == SIMD3<Int>(112, 160, 21), "unexpected dimensions")
        try expect(CTForearmVolumeAsset.expectedByteCount == 376_320, "unexpected byte count")
        try expect(abs(CTForearmVolumeAsset.physicalSizeMetres.x - 0.100_625) < 0.000_001, "bad X extent")
        try expect(abs(CTForearmVolumeAsset.physicalSizeMetres.y - 0.143_75) < 0.000_001, "bad Y extent")
        try expect(abs(CTForearmVolumeAsset.physicalSizeMetres.z - 0.060) < 0.000_001, "bad Z extent")
        try expect(AnatomicalLayerProjectionFeature.isEnabledByDefault == false, "feature flag must remain off")
    }

    private static func checkSurfaceDepthAbstraction() throws {
        let dimensions = SIMD3<Int>(4, 4, 4)
        var bytes = Data(repeating: 0, count: dimensions.x * dimensions.y * dimensions.z)
        for z in 0 ..< dimensions.z {
            for y in 0 ..< dimensions.y {
                bytes[z * dimensions.x * dimensions.y + y * dimensions.x + 1] = 120
                bytes[z * dimensions.x * dimensions.y + y * dimensions.x + 2] = 220
            }
        }
        let sampler = CTVisibleSurfaceDepthSampler(
            volume: try CTForearmVolumeData(bytes: bytes, dimensions: dimensions),
            stepCount: 256,
            accumulatedOpacityThreshold: 0.20
        )
        let ray = try require(CTVolumeRay(origin: SIMD3<Float>(-1, 0, 0), direction: SIMD3<Float>(1, 0, 0)))
        let surface = try require(sampler.firstVisibleSurface(along: ray, revealAnatomy: 0))
        let bone = try require(sampler.firstVisibleSurface(along: ray, revealAnatomy: 1))
        try expect(surface.volumeLocalPosition.x < bone.volumeLocalPosition.x, "bone hit must be deeper than surface hit")
        try expect(surface.distanceMetres > 0 && bone.distanceMetres > surface.distanceMetres, "physical depth must increase")
        let missedRay = try require(
            CTVolumeRay(origin: SIMD3<Float>(-1, 2, 0), direction: SIMD3<Float>(1, 0, 0))
        )
        try expect(sampler.firstVisibleSurface(
            along: missedRay,
            revealAnatomy: 0.5
        ) == nil, "missed ray must return nil")
    }

    private static func checkInvalidDataFailsClosed() throws {
        do {
            _ = try CTForearmVolumeData(bytes: Data(repeating: 0, count: 3), dimensions: SIMD3<Int>(2, 2, 2))
            throw CheckError.failed("invalid byte count was accepted")
        } catch CTForearmVolumeLoadError.invalidByteCount(let expected, let actual) {
            try expect(expected == 8 && actual == 3, "wrong invalid-size report")
        }

        do {
            _ = try CTForearmVolumeData.validatedAsset(
                bytes: Data(repeating: 0, count: CTForearmVolumeAsset.expectedByteCount)
            )
            throw CheckError.failed("same-size substituted asset was accepted")
        } catch CTForearmVolumeLoadError.invalidSHA256(let expected, let actual) {
            try expect(expected == CTForearmVolumeAsset.expectedSHA256, "wrong expected hash")
            try expect(actual != expected, "substituted asset must have a different hash")
        }
    }

    private static func checkBuiltAsset(projectRoot: String) throws {
        let url = URL(fileURLWithPath: projectRoot)
            .appendingPathComponent("UpperLimbPOC/CTVolume")
            .appendingPathComponent("\(CTForearmVolumeAsset.resourceName).r8")
        let data = try Data(contentsOf: url)
        try expect(data.count == CTForearmVolumeAsset.expectedByteCount, "asset byte count mismatch")
        let hash = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        try expect(hash == CTForearmVolumeAsset.expectedSHA256, "asset SHA256 mismatch: \(hash)")
    }

    private static func expect(_ condition: @autoclosure () -> Bool, _ message: String) throws {
        guard condition() else { throw CheckError.failed(message) }
    }

    private static func require<T>(_ value: T?) throws -> T {
        guard let value else { throw CheckError.failed("expected non-nil value") }
        return value
    }

    private enum CheckError: Error { case failed(String) }
}
