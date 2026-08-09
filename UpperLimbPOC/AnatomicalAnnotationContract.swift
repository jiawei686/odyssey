import Foundation

enum AnatomicalAnnotationProtocol {
    static let currentVersion = 1
    static let maximumIdentifierLength = 128
}

enum AnatomicalLayerProjectionFeature {
    static let isEnabledByDefault = false
    static let disclosure = "Illustrative anatomical model — not patient-specific imaging."
}

enum AnatomicalLayerTarget: String, CaseIterable, Codable, Equatable, Sendable {
    case skin
    case subcutaneousFat
    case muscle
    case bone
    case floating

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let rawValue = try container.decode(String.self)
        self = Self(rawValue: rawValue) ?? .floating
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

struct AnatomicalNormalizedScreenPoint: Codable, Equatable, Sendable {
    let x: Double
    let y: Double

    init(x: Double, y: Double) {
        self.x = x
        self.y = y
    }

    var isValid: Bool {
        x.isFinite && y.isFinite && (0 ... 1).contains(x) && (0 ... 1).contains(y)
    }
}

struct AnatomicalAnnotationFrameReference: Codable, Equatable, Sendable {
    let identifier: String
    let capturedAt: Date

    init(identifier: String, capturedAt: Date) {
        self.identifier = identifier
        self.capturedAt = capturedAt
    }

    var isValid: Bool {
        !identifier.isEmpty &&
            identifier.count <= AnatomicalAnnotationProtocol.maximumIdentifierLength &&
            capturedAt.timeIntervalSinceReferenceDate.isFinite
    }
}

enum AnatomicalAnnotationGeometryKind: String, Codable, Equatable, Sendable {
    case point
    case circle
}

struct AnatomicalAnnotationGeometry: Codable, Equatable, Sendable {
    let kind: AnatomicalAnnotationGeometryKind
    let center: AnatomicalNormalizedScreenPoint
    let normalizedRadius: Double?

    static func point(at center: AnatomicalNormalizedScreenPoint) -> Self {
        Self(kind: .point, center: center, normalizedRadius: nil)
    }

    static func circle(
        center: AnatomicalNormalizedScreenPoint,
        normalizedRadius: Double
    ) -> Self {
        Self(kind: .circle, center: center, normalizedRadius: normalizedRadius)
    }

    var isValid: Bool {
        guard center.isValid else { return false }
        switch kind {
        case .point:
            return normalizedRadius == nil
        case .circle:
            guard let normalizedRadius else { return false }
            return normalizedRadius.isFinite && normalizedRadius > 0 && normalizedRadius <= 0.5
        }
    }
}

struct AnatomicalAnnotationRequest: Codable, Equatable, Sendable {
    let annotationIdentifier: UUID
    let frame: AnatomicalAnnotationFrameReference
    let targetLayer: AnatomicalLayerTarget
    let geometry: AnatomicalAnnotationGeometry

    init(
        annotationIdentifier: UUID,
        frame: AnatomicalAnnotationFrameReference,
        targetLayer: AnatomicalLayerTarget,
        geometry: AnatomicalAnnotationGeometry
    ) {
        self.annotationIdentifier = annotationIdentifier
        self.frame = frame
        self.targetLayer = targetLayer
        self.geometry = geometry
    }

    private enum CodingKeys: String, CodingKey {
        case annotationIdentifier
        case frame
        case targetLayer
        case geometry
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        annotationIdentifier = try container.decode(UUID.self, forKey: .annotationIdentifier)
        frame = try container.decode(AnatomicalAnnotationFrameReference.self, forKey: .frame)
        // Requests produced before layer selection existed remain decodable, but
        // floating is deliberately non-projectable and therefore fails closed.
        targetLayer = try container.decodeIfPresent(
            AnatomicalLayerTarget.self,
            forKey: .targetLayer
        ) ?? .floating
        geometry = try container.decode(AnatomicalAnnotationGeometry.self, forKey: .geometry)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(annotationIdentifier, forKey: .annotationIdentifier)
        try container.encode(frame, forKey: .frame)
        try container.encode(targetLayer, forKey: .targetLayer)
        try container.encode(geometry, forKey: .geometry)
    }

    var isValid: Bool {
        frame.isValid && geometry.isValid
    }
}

enum AnatomicalAnnotationApplicationState: String, Codable, Equatable, Sendable {
    case applied
    case rejected
}

enum AnatomicalProjectionFailureReason: String, Codable, Equatable, Sendable {
    case featureDisabled
    case invalidRequest
    case frameMismatch
    case staleFrame
    case trackingUnavailable
    case trackingNotLive
    case insufficientTrackingConfidence
    case invalidRay
    case unsupportedTargetLayer
    case surfaceUnavailable
    case missedSurface
    case insufficientProjectionConfidence
}

struct AnatomicalProjectionVector3: Codable, Equatable, Sendable {
    let x: Double
    let y: Double
    let z: Double

    init(x: Double, y: Double, z: Double) {
        self.x = x
        self.y = y
        self.z = z
    }

    var isFinite: Bool {
        x.isFinite && y.isFinite && z.isFinite
    }
}

struct AnatomicalAnnotationLocalPlacement: Codable, Equatable, Sendable {
    let forearmLocalPosition: AnatomicalProjectionVector3
    let forearmLocalSurfaceNormal: AnatomicalProjectionVector3
    let forearmLocalRadiusMetres: Double?

    var isValid: Bool {
        guard forearmLocalPosition.isFinite, forearmLocalSurfaceNormal.isFinite else {
            return false
        }
        let normalLengthSquared =
            forearmLocalSurfaceNormal.x * forearmLocalSurfaceNormal.x +
            forearmLocalSurfaceNormal.y * forearmLocalSurfaceNormal.y +
            forearmLocalSurfaceNormal.z * forearmLocalSurfaceNormal.z
        guard normalLengthSquared > 0.99, normalLengthSquared < 1.01 else { return false }
        guard let forearmLocalRadiusMetres else { return true }
        return forearmLocalRadiusMetres.isFinite && forearmLocalRadiusMetres > 0
    }
}

struct AnatomicalAnnotationProjectionResult: Codable, Equatable, Sendable {
    let annotationIdentifier: UUID
    let frame: AnatomicalAnnotationFrameReference
    let targetLayer: AnatomicalLayerTarget
    let sourceGeometry: AnatomicalAnnotationGeometry
    let state: AnatomicalAnnotationApplicationState
    let projectionConfidence: Double
    let failureReason: AnatomicalProjectionFailureReason?
    let placement: AnatomicalAnnotationLocalPlacement?

    var isValid: Bool {
        guard frame.isValid,
              sourceGeometry.isValid,
              projectionConfidence.isFinite,
              (0 ... 1).contains(projectionConfidence)
        else {
            return false
        }

        switch state {
        case .applied:
            return failureReason == nil && placement?.isValid == true
        case .rejected:
            return failureReason != nil && placement == nil
        }
    }
}

enum AnatomicalAnnotationMessageKind: String, Codable, Equatable, Sendable {
    case projectionRequest
    case projectionResult
}

struct AnatomicalAnnotationMessagePayload: Codable, Equatable, Sendable {
    let kind: AnatomicalAnnotationMessageKind
    let request: AnatomicalAnnotationRequest?
    let result: AnatomicalAnnotationProjectionResult?

    static func projectionRequest(_ request: AnatomicalAnnotationRequest) -> Self {
        Self(kind: .projectionRequest, request: request, result: nil)
    }

    static func projectionResult(_ result: AnatomicalAnnotationProjectionResult) -> Self {
        Self(kind: .projectionResult, request: nil, result: result)
    }

    var isValid: Bool {
        switch kind {
        case .projectionRequest:
            return request?.isValid == true && result == nil
        case .projectionResult:
            return request == nil && result?.isValid == true
        }
    }
}

struct AnatomicalAnnotationWireMessage: Codable, Equatable, Sendable {
    let protocolVersion: Int
    let sessionID: UUID
    let messageID: UUID
    let sequenceNumber: UInt64
    let sentAt: Date
    let payload: AnatomicalAnnotationMessagePayload

    init(
        protocolVersion: Int = AnatomicalAnnotationProtocol.currentVersion,
        sessionID: UUID,
        messageID: UUID = UUID(),
        sequenceNumber: UInt64,
        sentAt: Date,
        payload: AnatomicalAnnotationMessagePayload
    ) {
        self.protocolVersion = protocolVersion
        self.sessionID = sessionID
        self.messageID = messageID
        self.sequenceNumber = sequenceNumber
        self.sentAt = sentAt
        self.payload = payload
    }

    var isStructurallyValid: Bool {
        protocolVersion == AnatomicalAnnotationProtocol.currentVersion &&
            sentAt.timeIntervalSinceReferenceDate.isFinite &&
            payload.isValid
    }
}
