import Foundation

enum RegistrationLandmarkID: String, Codable, CaseIterable, Hashable, Sendable {
    case elbowReference
    case wristCenter
    case distalRadius
    case distalUlna
    case indexMCP
    case indexPIP
    case indexDIP
}

enum LandmarkObservationSource: String, Codable, Sendable {
    case imageMarker
    case handSkeleton
    case manualHumanPlacement
    case sceneReconstructionSurface
    case enterpriseCameraModel
    case externalCalibratedCameraModel

    var suppliesNamedAnatomicalLandmarks: Bool {
        switch self {
        case .imageMarker, .handSkeleton, .manualHumanPlacement,
             .enterpriseCameraModel, .externalCalibratedCameraModel:
            true
        case .sceneReconstructionSurface:
            false
        }
    }

    var requiresEnterpriseEntitlement: Bool {
        self == .enterpriseCameraModel
    }
}

struct LandmarkVector3: Codable, Equatable, Sendable {
    let x: Double
    let y: Double
    let z: Double

    static let zero = LandmarkVector3(x: 0, y: 0, z: 0)

    static func + (lhs: Self, rhs: Self) -> Self {
        Self(x: lhs.x + rhs.x, y: lhs.y + rhs.y, z: lhs.z + rhs.z)
    }

    static func - (lhs: Self, rhs: Self) -> Self {
        Self(x: lhs.x - rhs.x, y: lhs.y - rhs.y, z: lhs.z - rhs.z)
    }

    static func * (lhs: Self, rhs: Double) -> Self {
        Self(x: lhs.x * rhs, y: lhs.y * rhs, z: lhs.z * rhs)
    }

    static func / (lhs: Self, rhs: Double) -> Self {
        Self(x: lhs.x / rhs, y: lhs.y / rhs, z: lhs.z / rhs)
    }

    var squaredLength: Double { dot(self) }
    var length: Double { sqrt(squaredLength) }

    func dot(_ other: Self) -> Double {
        x * other.x + y * other.y + z * other.z
    }

    func cross(_ other: Self) -> Self {
        Self(
            x: y * other.z - z * other.y,
            y: z * other.x - x * other.z,
            z: x * other.y - y * other.x
        )
    }

    func normalized(epsilon: Double = 1e-9) throws -> Self {
        let magnitude = length
        guard magnitude > epsilon else {
            throw HybridLandmarkRegistrationError.degenerateLandmarkFrame
        }
        return self / magnitude
    }
}

struct ModelRegistrationLandmark: Codable, Equatable, Sendable {
    let id: RegistrationLandmarkID
    let position: LandmarkVector3
    let humanReviewed: Bool
}

struct ObservedRegistrationLandmark: Codable, Equatable, Sendable {
    let id: RegistrationLandmarkID
    let position: LandmarkVector3
    let source: LandmarkObservationSource
    let isTracked: Bool
    let confidence: Double?
}

enum LandmarkRegistrationReadiness: String, Codable, Sendable {
    case insufficient
    case axisOnly
    case fullFrame
}

struct LandmarkRegistrationAssessment: Equatable, Sendable {
    let readiness: LandmarkRegistrationReadiness
    let matchedIDs: Set<RegistrationLandmarkID>
    let rejectedIDs: Set<RegistrationLandmarkID>
}

struct Matrix3x3: Equatable, Sendable {
    // Row-major storage.
    let values: [Double]

    init(values: [Double]) {
        precondition(values.count == 9)
        self.values = values
    }

    static let identity = Matrix3x3(values: [
        1, 0, 0,
        0, 1, 0,
        0, 0, 1
    ])

    init(column0: LandmarkVector3, column1: LandmarkVector3, column2: LandmarkVector3) {
        self.init(values: [
            column0.x, column1.x, column2.x,
            column0.y, column1.y, column2.y,
            column0.z, column1.z, column2.z
        ])
    }

    func applying(to point: LandmarkVector3) -> LandmarkVector3 {
        LandmarkVector3(
            x: values[0] * point.x + values[1] * point.y + values[2] * point.z,
            y: values[3] * point.x + values[4] * point.y + values[5] * point.z,
            z: values[6] * point.x + values[7] * point.y + values[8] * point.z
        )
    }

    var transposed: Matrix3x3 {
        Matrix3x3(values: [
            values[0], values[3], values[6],
            values[1], values[4], values[7],
            values[2], values[5], values[8]
        ])
    }

    static func * (lhs: Matrix3x3, rhs: Matrix3x3) -> Matrix3x3 {
        var result = Array(repeating: 0.0, count: 9)
        for row in 0..<3 {
            for column in 0..<3 {
                result[row * 3 + column] = (0..<3).reduce(0) { partial, index in
                    partial + lhs.values[row * 3 + index] * rhs.values[index * 3 + column]
                }
            }
        }
        return Matrix3x3(values: result)
    }
}

struct SimilarityTransform3D: Equatable, Sendable {
    let scale: Double
    let rotation: Matrix3x3
    let translation: LandmarkVector3

    func applying(to point: LandmarkVector3) -> LandmarkVector3 {
        rotation.applying(to: point) * scale + translation
    }
}

struct HybridLandmarkRegistrationSolution: Equatable, Sendable {
    let transform: SimilarityTransform3D
    let residualMillimetres: [RegistrationLandmarkID: Double]
    let rmsResidualMillimetres: Double
    let maximumResidualMillimetres: Double
}

enum HybridLandmarkRegistrationError: Error, Equatable {
    case missingRequiredLandmark(RegistrationLandmarkID)
    case unreviewedModelLandmark(RegistrationLandmarkID)
    case untrackedObservation(RegistrationLandmarkID)
    case unsupportedObservationSource(RegistrationLandmarkID)
    case invalidConfidence(RegistrationLandmarkID)
    case degenerateLandmarkFrame
    case invalidScale
}

enum HybridLandmarkRegistration {
    static let fullForearmFrame: Set<RegistrationLandmarkID> = [
        .elbowReference,
        .distalRadius,
        .distalUlna
    ]

    static let forearmAxis: Set<RegistrationLandmarkID> = [
        .elbowReference,
        .wristCenter
    ]

    static func assess(
        model: [ModelRegistrationLandmark],
        observed: [ObservedRegistrationLandmark],
        minimumConfidence: Double = 0.5
    ) -> LandmarkRegistrationAssessment {
        let reviewedModelIDs = Set(model.filter(\.humanReviewed).map(\.id))
        var accepted = Set<RegistrationLandmarkID>()
        var rejected = Set<RegistrationLandmarkID>()

        for observation in observed where reviewedModelIDs.contains(observation.id) {
            let confidenceIsUsable = observation.confidence.map {
                $0.isFinite && $0 >= minimumConfidence && $0 <= 1
            } ?? true

            if observation.isTracked,
               observation.source.suppliesNamedAnatomicalLandmarks,
               confidenceIsUsable {
                accepted.insert(observation.id)
            } else {
                rejected.insert(observation.id)
            }
        }

        let readiness: LandmarkRegistrationReadiness
        if fullForearmFrame.isSubset(of: accepted) {
            readiness = .fullFrame
        } else if forearmAxis.isSubset(of: accepted) {
            readiness = .axisOnly
        } else {
            readiness = .insufficient
        }

        return LandmarkRegistrationAssessment(
            readiness: readiness,
            matchedIDs: accepted,
            rejectedIDs: rejected
        )
    }

    static func solveForearmFrame(
        model: [ModelRegistrationLandmark],
        observed: [ObservedRegistrationLandmark]
    ) throws -> HybridLandmarkRegistrationSolution {
        let modelByID = Dictionary(uniqueKeysWithValues: model.map { ($0.id, $0) })
        let observedByID = Dictionary(uniqueKeysWithValues: observed.map { ($0.id, $0) })

        for id in fullForearmFrame {
            guard let modelLandmark = modelByID[id] else {
                throw HybridLandmarkRegistrationError.missingRequiredLandmark(id)
            }
            guard modelLandmark.humanReviewed else {
                throw HybridLandmarkRegistrationError.unreviewedModelLandmark(id)
            }
            guard let observation = observedByID[id] else {
                throw HybridLandmarkRegistrationError.missingRequiredLandmark(id)
            }
            guard observation.isTracked else {
                throw HybridLandmarkRegistrationError.untrackedObservation(id)
            }
            guard observation.source.suppliesNamedAnatomicalLandmarks else {
                throw HybridLandmarkRegistrationError.unsupportedObservationSource(id)
            }
            if let confidence = observation.confidence,
               (!confidence.isFinite || confidence < 0 || confidence > 1) {
                throw HybridLandmarkRegistrationError.invalidConfidence(id)
            }
        }

        let modelPoints = try requiredPoints(from: modelByID.mapValues(\.position))
        let observedPoints = try requiredPoints(from: observedByID.mapValues(\.position))
        let modelBasis = try forearmBasis(points: modelPoints)
        let observedBasis = try forearmBasis(points: observedPoints)
        let rotation = observedBasis * modelBasis.transposed

        let modelCentroid = centroid(of: Array(modelPoints.values))
        let observedCentroid = centroid(of: Array(observedPoints.values))
        var numerator = 0.0
        var denominator = 0.0

        for id in fullForearmFrame {
            guard let modelPoint = modelPoints[id], let observedPoint = observedPoints[id] else {
                throw HybridLandmarkRegistrationError.missingRequiredLandmark(id)
            }
            let centeredModel = modelPoint - modelCentroid
            let rotatedModel = rotation.applying(to: centeredModel)
            numerator += (observedPoint - observedCentroid).dot(rotatedModel)
            denominator += centeredModel.squaredLength
        }

        guard denominator > 1e-12 else {
            throw HybridLandmarkRegistrationError.degenerateLandmarkFrame
        }
        let scale = numerator / denominator
        guard scale.isFinite, scale > 0 else {
            throw HybridLandmarkRegistrationError.invalidScale
        }

        let translation = observedCentroid - rotation.applying(to: modelCentroid) * scale
        let transform = SimilarityTransform3D(
            scale: scale,
            rotation: rotation,
            translation: translation
        )

        var residuals = [RegistrationLandmarkID: Double]()
        for id in fullForearmFrame {
            guard let modelPoint = modelPoints[id], let observedPoint = observedPoints[id] else {
                throw HybridLandmarkRegistrationError.missingRequiredLandmark(id)
            }
            residuals[id] = (transform.applying(to: modelPoint) - observedPoint).length * 1_000
        }

        let squaredResiduals = residuals.values.map { $0 * $0 }
        let rms = sqrt(squaredResiduals.reduce(0, +) / Double(squaredResiduals.count))
        return HybridLandmarkRegistrationSolution(
            transform: transform,
            residualMillimetres: residuals,
            rmsResidualMillimetres: rms,
            maximumResidualMillimetres: residuals.values.max() ?? 0
        )
    }

    private static func requiredPoints(
        from points: [RegistrationLandmarkID: LandmarkVector3]
    ) throws -> [RegistrationLandmarkID: LandmarkVector3] {
        var result = [RegistrationLandmarkID: LandmarkVector3]()
        for id in fullForearmFrame {
            guard let point = points[id] else {
                throw HybridLandmarkRegistrationError.missingRequiredLandmark(id)
            }
            result[id] = point
        }
        return result
    }

    private static func forearmBasis(
        points: [RegistrationLandmarkID: LandmarkVector3]
    ) throws -> Matrix3x3 {
        guard let elbow = points[.elbowReference],
              let radius = points[.distalRadius],
              let ulna = points[.distalUlna] else {
            throw HybridLandmarkRegistrationError.degenerateLandmarkFrame
        }

        let wrist = (radius + ulna) / 2
        let longAxis = try (wrist - elbow).normalized()
        let radialDirection = radius - wrist
        let radialPerpendicular = radialDirection - longAxis * radialDirection.dot(longAxis)
        let radialAxis = try radialPerpendicular.normalized()
        let normalAxis = try longAxis.cross(radialAxis).normalized()
        return Matrix3x3(
            column0: longAxis,
            column1: radialAxis,
            column2: normalAxis
        )
    }

    private static func centroid(of points: [LandmarkVector3]) -> LandmarkVector3 {
        points.reduce(.zero, +) / Double(points.count)
    }
}
