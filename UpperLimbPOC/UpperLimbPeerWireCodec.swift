import Foundation

enum UpperLimbPeerWirePayload {
    case overlaySnapshot(OverlaySnapshot)
    case jointFrame(UpperLimbJointFrame)
    case clinicianGuidance(ClinicianGuidanceMessage)
    case odysseyClinicalSession(OdysseyClinicalSessionMessage)
}

enum UpperLimbPeerWireError: Error, Equatable {
    case unsupportedPayload
}

enum UpperLimbPeerWireCodec {
    static func encode(_ snapshot: OverlaySnapshot) throws -> Data {
        // Keep the existing raw snapshot representation for compatibility with
        // already-installed companion and Vision builds.
        try JSONEncoder().encode(snapshot)
    }

    static func encode(_ frame: UpperLimbJointFrame) throws -> Data {
        try JSONEncoder().encode(UpperLimbPeerEnvelope(jointFrame: frame))
    }

    static func encode(_ message: ClinicianGuidanceMessage) throws -> Data {
        try ClinicianGuidanceWireCodec.encode(message)
    }

    static func encode(_ message: OdysseyClinicalSessionMessage) throws -> Data {
        try OdysseyClinicalSessionWireCodec().encode(message)
    }

    static func decode(_ packet: Data) throws -> UpperLimbPeerWirePayload {
        if let message = try OdysseyClinicalSessionWireCodec()
            .decodeIfOdysseyClinicalSession(packet) {
            return .odysseyClinicalSession(message)
        }
        if let message = try? ClinicianGuidanceWireCodec.decode(packet) {
            return .clinicianGuidance(message)
        }
        let decoder = JSONDecoder()
        if let envelope = try? decoder.decode(UpperLimbPeerEnvelope.self, from: packet),
           envelope.isSupported {
            return .jointFrame(envelope.jointFrame)
        }
        if let snapshot = try? decoder.decode(OverlaySnapshot.self, from: packet) {
            return .overlaySnapshot(snapshot)
        }
        throw UpperLimbPeerWireError.unsupportedPayload
    }
}
