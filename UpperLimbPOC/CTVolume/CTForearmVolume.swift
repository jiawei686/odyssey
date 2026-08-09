#if DEBUG
import CryptoKit
import Foundation
import simd

enum CTForearmVolumeAsset {
    static let resourceName = "visible-human-male-forearm-1680-1740"
    static let resourceExtension = "r8"
    static let coordinateRootIdentifier = "GenericForearmCoordinateRoot"
    static let dimensions = SIMD3<Int>(112, 160, 21)
    static let spacingMetres = SIMD3<Float>(0.000_898_437_5, 0.000_898_437_5, 0.003)
    static let expectedByteCount = dimensions.x * dimensions.y * dimensions.z
    static let expectedSHA256 = "43244b476c3e409dc1b32d2f55982b4f3946c058063b4d187c617b8243ef3a2d"

    static let physicalSizeMetres = SIMD3<Float>(
        Float(dimensions.x) * spacingMetres.x,
        Float(dimensions.y) * spacingMetres.y,
        Float(dimensions.z - 1) * spacingMetres.z
    )

    // Centred volume coordinates use -0.5...+0.5. CT +X maps to forearm +X,
    // increasing slice index maps to forearm +Y, and CT image +Y maps to -Z.
    static let volumeToForearmLocal = matrix_float4x4(
        SIMD4<Float>(physicalSizeMetres.x, 0, 0, 0),
        SIMD4<Float>(0, 0, -physicalSizeMetres.y, 0),
        SIMD4<Float>(0, physicalSizeMetres.z, 0, 0),
        SIMD4<Float>(0, 0, 0, 1)
    )

    static func forearmLocalPoint(fromVolumeLocal point: SIMD3<Float>) -> SIMD3<Float> {
        let mapped = volumeToForearmLocal * SIMD4<Float>(point, 1)
        return SIMD3<Float>(mapped.x, mapped.y, mapped.z)
    }
}

enum CTForearmVolumeLoadError: Error, Equatable {
    case missingResource
    case invalidByteCount(expected: Int, actual: Int)
    case invalidSHA256(expected: String, actual: String)
}

struct CTForearmVolumeData: Sendable {
    let bytes: Data
    let dimensions: SIMD3<Int>

    init(bytes: Data, dimensions: SIMD3<Int> = CTForearmVolumeAsset.dimensions) throws {
        let expected = dimensions.x * dimensions.y * dimensions.z
        guard bytes.count == expected else {
            throw CTForearmVolumeLoadError.invalidByteCount(expected: expected, actual: bytes.count)
        }
        self.bytes = bytes
        self.dimensions = dimensions
    }

    static func load(from bundle: Bundle = .main) throws -> Self {
        guard let url = bundle.url(
            forResource: CTForearmVolumeAsset.resourceName,
            withExtension: CTForearmVolumeAsset.resourceExtension
        ) else { throw CTForearmVolumeLoadError.missingResource }
        return try validatedAsset(bytes: Data(contentsOf: url))
    }

    static func validatedAsset(bytes: Data) throws -> Self {
        let volume = try Self(bytes: bytes)
        let hash = SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined()
        guard hash == CTForearmVolumeAsset.expectedSHA256 else {
            throw CTForearmVolumeLoadError.invalidSHA256(
                expected: CTForearmVolumeAsset.expectedSHA256,
                actual: hash
            )
        }
        return volume
    }
}

/// A screen/camera ray after inverse pose and physical-scale conversion into
/// centred CT volume coordinates.
struct CTVolumeRay: Equatable, Sendable {
    let origin: SIMD3<Float>
    let direction: SIMD3<Float>

    init?(origin: SIMD3<Float>, direction: SIMD3<Float>) {
        guard origin.allFinite, direction.allFinite else { return nil }
        let length = simd_length(direction)
        guard length.isFinite, length > 0.000_001 else { return nil }
        self.origin = origin
        self.direction = direction / length
    }
}

struct CTVisibleSurfaceHit: Equatable, Sendable {
    let distanceInVolumeCoordinates: Float
    let distanceMetres: Float
    let volumeLocalPosition: SIMD3<Float>
    let forearmLocalPosition: SIMD3<Float>
    let density: Float
}

/// Finds the transfer-function-visible depth along a screen-derived
/// volume-local ray.
protocol CTVisibleSurfaceDepthProviding: Sendable {
    func firstVisibleSurface(
        along ray: CTVolumeRay,
        revealAnatomy: Float
    ) -> CTVisibleSurfaceHit?
}

enum CTVolumeTransferFunction {
    static func opacity(density: Float, revealAnatomy: Float) -> Float {
        let reveal = min(max(revealAnatomy, 0), 1)
        let soft = smoothstep(0.34, 0.48, density)
            * (1 - smoothstep(0.58, 0.72, density))
        let bone = smoothstep(0.58, 0.76, density)
        let softOpacity = soft * 0.16 * pow(1 - reveal, 1.35)
        let boneOpacity = bone * 0.42 * reveal
        return max(softOpacity, boneOpacity)
    }

    private static func smoothstep(_ edge0: Float, _ edge1: Float, _ value: Float) -> Float {
        let t = min(max((value - edge0) / (edge1 - edge0), 0), 1)
        return t * t * (3 - 2 * t)
    }
}

struct CTVisibleSurfaceDepthSampler: CTVisibleSurfaceDepthProviding {
    let volume: CTForearmVolumeData
    let stepCount: Int
    let accumulatedOpacityThreshold: Float

    init(
        volume: CTForearmVolumeData,
        stepCount: Int = 192,
        accumulatedOpacityThreshold: Float = 0.35
    ) {
        self.volume = volume
        self.stepCount = max(stepCount, 16)
        self.accumulatedOpacityThreshold = min(max(accumulatedOpacityThreshold, 0.05), 0.95)
    }

    func firstVisibleSurface(
        along ray: CTVolumeRay,
        revealAnatomy: Float
    ) -> CTVisibleSurfaceHit? {
        guard let interval = intersectionInterval(for: ray) else { return nil }
        let distance = interval.exit - interval.entry
        guard distance > 0 else { return nil }
        let step = distance / Float(stepCount)
        var accumulatedOpacity: Float = 0

        for sampleIndex in 0 ... stepCount {
            let rayDistance = interval.entry + Float(sampleIndex) * step
            let point = ray.origin + ray.direction * rayDistance
            let density = sampleTrilinear(at: point + SIMD3<Float>(repeating: 0.5))
            let opacity = CTVolumeTransferFunction.opacity(
                density: density,
                revealAnatomy: revealAnatomy
            )
            accumulatedOpacity += (1 - accumulatedOpacity) * opacity
            if accumulatedOpacity >= accumulatedOpacityThreshold {
                let forearmPoint = CTForearmVolumeAsset.forearmLocalPoint(fromVolumeLocal: point)
                let forearmOrigin = CTForearmVolumeAsset.forearmLocalPoint(fromVolumeLocal: ray.origin)
                return CTVisibleSurfaceHit(
                    distanceInVolumeCoordinates: rayDistance,
                    distanceMetres: simd_distance(forearmOrigin, forearmPoint),
                    volumeLocalPosition: point,
                    forearmLocalPosition: forearmPoint,
                    density: density
                )
            }
        }
        return nil
    }

    private func intersectionInterval(for ray: CTVolumeRay) -> (entry: Float, exit: Float)? {
        var entry = -Float.infinity
        var exit = Float.infinity
        for axis in 0 ..< 3 {
            let origin = ray.origin[axis]
            let direction = ray.direction[axis]
            if abs(direction) < 0.000_001 {
                guard (-0.5 ... 0.5).contains(origin) else { return nil }
                continue
            }
            var near = (-0.5 - origin) / direction
            var far = (0.5 - origin) / direction
            if near > far { swap(&near, &far) }
            entry = max(entry, near)
            exit = min(exit, far)
            guard entry <= exit else { return nil }
        }
        exit = max(exit, 0)
        entry = max(entry, 0)
        return entry <= exit ? (entry, exit) : nil
    }

    private func sampleTrilinear(at texturePoint: SIMD3<Float>) -> Float {
        let clamped = simd_clamp(texturePoint, SIMD3<Float>(repeating: 0), SIMD3<Float>(repeating: 1))
        let scaled = clamped * SIMD3<Float>(
            Float(volume.dimensions.x - 1),
            Float(volume.dimensions.y - 1),
            Float(volume.dimensions.z - 1)
        )
        let x0 = Int(floor(scaled.x)); let y0 = Int(floor(scaled.y)); let z0 = Int(floor(scaled.z))
        let x1 = min(x0 + 1, volume.dimensions.x - 1)
        let y1 = min(y0 + 1, volume.dimensions.y - 1)
        let z1 = min(z0 + 1, volume.dimensions.z - 1)
        let fx = scaled.x - Float(x0); let fy = scaled.y - Float(y0); let fz = scaled.z - Float(z0)

        func voxel(_ x: Int, _ y: Int, _ z: Int) -> Float {
            let index = z * volume.dimensions.x * volume.dimensions.y
                + y * volume.dimensions.x + x
            return Float(volume.bytes[index]) / 255
        }
        func lerp(_ a: Float, _ b: Float, _ t: Float) -> Float { a + (b - a) * t }
        let c00 = lerp(voxel(x0, y0, z0), voxel(x1, y0, z0), fx)
        let c10 = lerp(voxel(x0, y1, z0), voxel(x1, y1, z0), fx)
        let c01 = lerp(voxel(x0, y0, z1), voxel(x1, y0, z1), fx)
        let c11 = lerp(voxel(x0, y1, z1), voxel(x1, y1, z1), fx)
        return lerp(lerp(c00, c10, fy), lerp(c01, c11, fy), fz)
    }
}

private extension SIMD3 where Scalar == Float {
    var allFinite: Bool { x.isFinite && y.isFinite && z.isFinite }
}
#endif
