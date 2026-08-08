import Foundation

@main
struct UpperLimbPeerWireCheck {
    static func main() throws {
        try legacySnapshotRemainsRawAndDecodable()
        try jointFrameUsesTaggedEnvelope()
        try unsupportedPayloadIsRejected()
        print("Upper-limb peer wire checks passed")
    }

    private static func legacySnapshotRemainsRawAndDecodable() throws {
        let snapshot = OverlaySnapshot(
            regionID: "rightUpperLimb",
            x: 0.1,
            y: -0.2,
            z: -0.7,
            pitchDegrees: -90,
            yawDegrees: 5,
            rollDegrees: 0,
            scale: 1,
            opacity: 0.7,
            tintID: "cyan",
            locked: true,
            sectionVisible: true,
            normalizedSlicePosition: 0.5,
            sectionOpacity: 0.68,
            selectedSliceIndex: 2,
            sliceCount: 5
        )
        let packet = try UpperLimbPeerWireCodec.encode(snapshot)
        guard case .overlaySnapshot(let decoded) = try UpperLimbPeerWireCodec.decode(packet) else {
            throw CheckFailure(message: "legacy snapshot packet changed type")
        }
        try require(decoded == snapshot, "legacy raw snapshot must round-trip")
    }

    private static func jointFrameUsesTaggedEnvelope() throws {
        let frame = UpperLimbJointFrame(
            sessionID: UUID(),
            calibrationID: UUID(),
            senderClockID: UUID(),
            sequence: 1,
            capturedAtMonotonic: 12,
            observations: []
        )
        let packet = try UpperLimbPeerWireCodec.encode(frame)
        guard case .jointFrame(let decoded) = try UpperLimbPeerWireCodec.decode(packet) else {
            throw CheckFailure(message: "joint frame packet lost its type")
        }
        try require(decoded == frame, "joint frame must round-trip")
    }

    private static func unsupportedPayloadIsRejected() throws {
        do {
            _ = try UpperLimbPeerWireCodec.decode(Data("{\"unknown\":true}".utf8))
            throw CheckFailure(message: "unknown packet must fail closed")
        } catch UpperLimbPeerWireError.unsupportedPayload {
            // Expected.
        }
    }

    private static func require(_ condition: Bool, _ message: String) throws {
        guard condition else { throw CheckFailure(message: message) }
    }
}

private struct CheckFailure: Error {
    let message: String
}
