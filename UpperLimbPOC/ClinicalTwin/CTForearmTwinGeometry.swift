#if DEBUG
import Foundation
import simd

struct CTForearmTwinMeshPart: Equatable, Sendable {
    let positions: [SIMD3<Float>]
    let normals: [SIMD3<Float>]
    let indices: [UInt32]
    let sourceVoxelCount: Int

    var triangleCount: Int { indices.count / 3 }

    var longitudinalExtent: Float {
        guard let minimum = positions.map(\.y).min(),
              let maximum = positions.map(\.y).max() else { return 0 }
        return maximum - minimum
    }
}

struct CTForearmTwinGeometry: Equatable, Sendable {
    let softTissue: CTForearmTwinMeshPart
    let pairedBoneA: CTForearmTwinMeshPart
    let pairedBoneB: CTForearmTwinMeshPart
    let rendererRoute = ClinicalTwinRendererRoute.ctDerivedMeshFallback
}

enum CTForearmTwinGeometryError: Error, Equatable {
    case invalidSpacing
    case noSoftTissueComponent
    case fewerThanTwoBoneComponents(actual: Int)
    case tooManyVertices
}

enum CTForearmTwinGeometryBuilder {
    static let softTissueThreshold: UInt8 = 80
    static let boneThreshold: UInt8 = 160

    static func build(
        volume: CTForearmVolumeData,
        spacingMetres: SIMD3<Float>
    ) throws -> CTForearmTwinGeometry {
        guard spacingMetres.x.isFinite, spacingMetres.x > 0,
              spacingMetres.y.isFinite, spacingMetres.y > 0,
              spacingMetres.z.isFinite, spacingMetres.z > 0 else {
            throw CTForearmTwinGeometryError.invalidSpacing
        }

        let voxels = [UInt8](volume.bytes)
        let dimensions = volume.dimensions
        let softLabels = labelComponents(
            voxels: voxels,
            dimensions: dimensions,
            includes: { $0 >= softTissueThreshold }
        )
        guard let softComponent = softLabels.components.max(by: {
            $0.voxelCount < $1.voxelCount
        }) else {
            throw CTForearmTwinGeometryError.noSoftTissueComponent
        }
        let softMask = softLabels.labels.map { $0 == softComponent.label }

        let boneLabels = labelComponents(
            voxels: voxels,
            dimensions: dimensions,
            includes: { value in value >= boneThreshold },
            allowed: softMask
        )
        let boneComponents = boneLabels.components
            .sorted { lhs, rhs in
                if lhs.voxelCount != rhs.voxelCount {
                    return lhs.voxelCount > rhs.voxelCount
                }
                return lhs.label < rhs.label
            }
            .prefix(2)
        guard boneComponents.count == 2 else {
            throw CTForearmTwinGeometryError.fewerThanTwoBoneComponents(
                actual: boneComponents.count
            )
        }
        let orderedBones = boneComponents.sorted { lhs, rhs in
            lhs.centroidX < rhs.centroidX
        }
        let boneAMask = boneLabels.labels.map { $0 == orderedBones[0].label }
        let boneBMask = boneLabels.labels.map { $0 == orderedBones[1].label }

        return CTForearmTwinGeometry(
            softTissue: try makeSurface(
                mask: softMask,
                dimensions: dimensions,
                spacingMetres: spacingMetres,
                sourceVoxelCount: softComponent.voxelCount
            ),
            pairedBoneA: try makeSurface(
                mask: boneAMask,
                dimensions: dimensions,
                spacingMetres: spacingMetres,
                sourceVoxelCount: orderedBones[0].voxelCount
            ),
            pairedBoneB: try makeSurface(
                mask: boneBMask,
                dimensions: dimensions,
                spacingMetres: spacingMetres,
                sourceVoxelCount: orderedBones[1].voxelCount
            )
        )
    }

    private struct ComponentSummary {
        let label: Int32
        let voxelCount: Int
        let centroidX: Double
    }

    private struct LabelResult {
        let labels: [Int32]
        let components: [ComponentSummary]
    }

    private static func labelComponents(
        voxels: [UInt8],
        dimensions: SIMD3<Int>,
        includes: (UInt8) -> Bool,
        allowed: [Bool]? = nil
    ) -> LabelResult {
        var labels = [Int32](repeating: 0, count: voxels.count)
        var components: [ComponentSummary] = []
        var nextLabel: Int32 = 1
        var queue: [Int] = []
        queue.reserveCapacity(voxels.count)

        for seed in voxels.indices {
            guard labels[seed] == 0,
                  allowed?[seed] != false,
                  includes(voxels[seed]) else { continue }
            queue.removeAll(keepingCapacity: true)
            queue.append(seed)
            labels[seed] = nextLabel
            var cursor = 0
            var voxelCount = 0
            var sumX = 0

            while cursor < queue.count {
                let current = queue[cursor]
                cursor += 1
                voxelCount += 1
                let coordinate = coordinate(
                    for: current,
                    dimensions: dimensions
                )
                sumX += coordinate.x
                for neighbor in neighbors(
                    of: coordinate,
                    dimensions: dimensions
                ) {
                    let neighborIndex = index(
                        x: neighbor.x,
                        y: neighbor.y,
                        z: neighbor.z,
                        dimensions: dimensions
                    )
                    guard labels[neighborIndex] == 0,
                          allowed?[neighborIndex] != false,
                          includes(voxels[neighborIndex]) else { continue }
                    labels[neighborIndex] = nextLabel
                    queue.append(neighborIndex)
                }
            }

            components.append(
                ComponentSummary(
                    label: nextLabel,
                    voxelCount: voxelCount,
                    centroidX: Double(sumX) / Double(voxelCount)
                )
            )
            nextLabel += 1
        }
        return LabelResult(labels: labels, components: components)
    }

    private enum FaceDirection: CaseIterable {
        case negativeX
        case positiveX
        case negativeY
        case positiveY
        case negativeZ
        case positiveZ

        var sourceOffset: SIMD3<Int> {
            switch self {
            case .negativeX: SIMD3<Int>(-1, 0, 0)
            case .positiveX: SIMD3<Int>(1, 0, 0)
            case .negativeY: SIMD3<Int>(0, -1, 0)
            case .positiveY: SIMD3<Int>(0, 1, 0)
            case .negativeZ: SIMD3<Int>(0, 0, -1)
            case .positiveZ: SIMD3<Int>(0, 0, 1)
            }
        }
    }

    private static func makeSurface(
        mask: [Bool],
        dimensions: SIMD3<Int>,
        spacingMetres: SIMD3<Float>,
        sourceVoxelCount: Int
    ) throws -> CTForearmTwinMeshPart {
        var positions: [SIMD3<Float>] = []
        var normals: [SIMD3<Float>] = []
        var indices: [UInt32] = []
        positions.reserveCapacity(sourceVoxelCount * 4)
        normals.reserveCapacity(sourceVoxelCount * 4)
        indices.reserveCapacity(sourceVoxelCount * 6)

        let longitudinalStep = 1 / Float(dimensions.z)
        for sourceIndex in mask.indices where mask[sourceIndex] {
            let point = coordinate(for: sourceIndex, dimensions: dimensions)
            for direction in FaceDirection.allCases {
                let neighbor = point &+ direction.sourceOffset
                let neighborIsInside = isInside(
                    neighbor,
                    dimensions: dimensions
                ) && mask[index(
                    x: neighbor.x,
                    y: neighbor.y,
                    z: neighbor.z,
                    dimensions: dimensions
                )]
                guard !neighborIsInside else { continue }

                let face = faceGeometry(
                    direction: direction,
                    coordinate: point,
                    dimensions: dimensions,
                    spacingMetres: spacingMetres,
                    longitudinalStep: longitudinalStep
                )
                guard positions.count <= Int(UInt32.max) - 4 else {
                    throw CTForearmTwinGeometryError.tooManyVertices
                }
                let base = UInt32(positions.count)
                let halfU = face.u * 0.5
                let halfV = face.v * 0.5
                positions.append(face.center - halfU - halfV)
                positions.append(face.center + halfU - halfV)
                positions.append(face.center + halfU + halfV)
                positions.append(face.center - halfU + halfV)
                normals.append(contentsOf: repeatElement(face.normal, count: 4))
                indices.append(contentsOf: [
                    base, base + 1, base + 2,
                    base, base + 2, base + 3
                ])
            }
        }

        return CTForearmTwinMeshPart(
            positions: positions,
            normals: normals,
            indices: indices,
            sourceVoxelCount: sourceVoxelCount
        )
    }

    private static func faceGeometry(
        direction: FaceDirection,
        coordinate: SIMD3<Int>,
        dimensions: SIMD3<Int>,
        spacingMetres: SIMD3<Float>,
        longitudinalStep: Float
    ) -> (
        center: SIMD3<Float>,
        normal: SIMD3<Float>,
        u: SIMD3<Float>,
        v: SIMD3<Float>
    ) {
        let baseCenter = SIMD3<Float>(
            (Float(coordinate.x) + 0.5 - Float(dimensions.x) * 0.5)
                * spacingMetres.x,
            (Float(coordinate.z) + 0.5) * longitudinalStep - 0.5,
            -(Float(coordinate.y) + 0.5 - Float(dimensions.y) * 0.5)
                * spacingMetres.y
        )
        let x = SIMD3<Float>(spacingMetres.x, 0, 0)
        let longitudinal = SIMD3<Float>(0, longitudinalStep, 0)
        let crossSectionY = SIMD3<Float>(0, 0, spacingMetres.y)

        switch direction {
        case .negativeX:
            return (
                baseCenter - x * 0.5,
                SIMD3<Float>(-1, 0, 0),
                -longitudinal,
                crossSectionY
            )
        case .positiveX:
            return (
                baseCenter + x * 0.5,
                SIMD3<Float>(1, 0, 0),
                longitudinal,
                crossSectionY
            )
        case .negativeY:
            return (
                baseCenter + crossSectionY * 0.5,
                SIMD3<Float>(0, 0, 1),
                x,
                longitudinal
            )
        case .positiveY:
            return (
                baseCenter - crossSectionY * 0.5,
                SIMD3<Float>(0, 0, -1),
                -x,
                longitudinal
            )
        case .negativeZ:
            return (
                baseCenter - longitudinal * 0.5,
                SIMD3<Float>(0, -1, 0),
                x,
                crossSectionY
            )
        case .positiveZ:
            return (
                baseCenter + longitudinal * 0.5,
                SIMD3<Float>(0, 1, 0),
                crossSectionY,
                x
            )
        }
    }

    private static func coordinate(
        for index: Int,
        dimensions: SIMD3<Int>
    ) -> SIMD3<Int> {
        let plane = dimensions.x * dimensions.y
        let z = index / plane
        let remainder = index - z * plane
        let y = remainder / dimensions.x
        let x = remainder - y * dimensions.x
        return SIMD3<Int>(x, y, z)
    }

    private static func index(
        x: Int,
        y: Int,
        z: Int,
        dimensions: SIMD3<Int>
    ) -> Int {
        z * dimensions.x * dimensions.y + y * dimensions.x + x
    }

    private static func neighbors(
        of point: SIMD3<Int>,
        dimensions: SIMD3<Int>
    ) -> [SIMD3<Int>] {
        FaceDirection.allCases.compactMap { direction in
            let candidate = point &+ direction.sourceOffset
            return isInside(candidate, dimensions: dimensions)
                ? candidate
                : nil
        }
    }

    private static func isInside(
        _ point: SIMD3<Int>,
        dimensions: SIMD3<Int>
    ) -> Bool {
        point.x >= 0 && point.x < dimensions.x
            && point.y >= 0 && point.y < dimensions.y
            && point.z >= 0 && point.z < dimensions.z
    }
}
#endif
