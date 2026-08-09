import Foundation

@main
enum AnatomicalAnnotationContractCheck {
    static func main() throws {
        try layerVocabularyIsStable()
        try pointAndCircleMessagesRoundTrip()
        try malformedCoordinatesFailClosed()
        try legacyAndUnknownLayersRemainDecodableButNonProjectable()
        try clinicianGuidanceVersionRemainsUnchanged()
        print("Anatomical-annotation contract checks passed")
    }

    private static func layerVocabularyIsStable() throws {
        try require(
            AnatomicalLayerTarget.allCases == [
                .skin,
                .subcutaneousFat,
                .muscle,
                .bone,
                .floating
            ],
            "anatomical target vocabulary must remain stable"
        )
        try require(
            !AnatomicalLayerProjectionFeature.isEnabledByDefault,
            "experimental layer projection must be OFF by default"
        )
        try require(
            AnatomicalLayerProjectionFeature.disclosure ==
                "Illustrative anatomical model — not patient-specific imaging.",
            "preview disclosure must be exact"
        )
    }

    private static func pointAndCircleMessagesRoundTrip() throws {
        let frame = AnatomicalAnnotationFrameReference(
            identifier: "frame-42",
            capturedAt: Date(timeIntervalSince1970: 1_786_257_600.125)
        )
        let pointRequest = AnatomicalAnnotationRequest(
            annotationIdentifier: UUID(uuidString: "11111111-1111-1111-1111-111111111111")!,
            frame: frame,
            targetLayer: .muscle,
            geometry: .point(at: .init(x: 0.4, y: 0.6))
        )
        let circleRequest = AnatomicalAnnotationRequest(
            annotationIdentifier: UUID(uuidString: "22222222-2222-2222-2222-222222222222")!,
            frame: frame,
            targetLayer: .skin,
            geometry: .circle(center: .init(x: 0.5, y: 0.5), normalizedRadius: 0.1)
        )
        let appliedCircle = AnatomicalAnnotationProjectionResult(
            annotationIdentifier: circleRequest.annotationIdentifier,
            frame: frame,
            targetLayer: .skin,
            sourceGeometry: circleRequest.geometry,
            state: .applied,
            projectionConfidence: 0.94,
            failureReason: nil,
            placement: AnatomicalAnnotationLocalPlacement(
                forearmLocalPosition: .init(x: 0, y: 0, z: 0.05),
                forearmLocalSurfaceNormal: .init(x: 0, y: 0, z: 1),
                forearmLocalRadiusMetres: 0.012
            )
        )
        let messages = [
            AnatomicalAnnotationWireMessage(
                sessionID: UUID(uuidString: "AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA")!,
                sequenceNumber: 1,
                sentAt: frame.capturedAt,
                payload: .projectionRequest(pointRequest)
            ),
            AnatomicalAnnotationWireMessage(
                sessionID: UUID(uuidString: "AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA")!,
                sequenceNumber: 2,
                sentAt: frame.capturedAt,
                payload: .projectionRequest(circleRequest)
            ),
            AnatomicalAnnotationWireMessage(
                sessionID: UUID(uuidString: "AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA")!,
                sequenceNumber: 3,
                sentAt: frame.capturedAt,
                payload: .projectionResult(appliedCircle)
            )
        ]
        let codec = AnatomicalAnnotationWireCodec()
        for message in messages {
            let encoded = try codec.encode(message)
            let decoded = try codec.decode(encoded)
            try require(decoded == message, "point/circle annotation message must round-trip")
        }
    }

    private static func malformedCoordinatesFailClosed() throws {
        let frame = AnatomicalAnnotationFrameReference(
            identifier: "frame-invalid",
            capturedAt: Date(timeIntervalSince1970: 100)
        )
        let invalid = AnatomicalAnnotationRequest(
            annotationIdentifier: UUID(),
            frame: frame,
            targetLayer: .skin,
            geometry: .point(at: .init(x: 1.2, y: 0.5))
        )
        let message = AnatomicalAnnotationWireMessage(
            sessionID: UUID(),
            sequenceNumber: 1,
            sentAt: frame.capturedAt,
            payload: .projectionRequest(invalid)
        )
        do {
            _ = try AnatomicalAnnotationWireCodec().encode(message)
            throw CheckFailure(message: "out-of-range screen coordinates must be rejected")
        } catch AnatomicalAnnotationWireCodecError.malformedMessage {
            // Expected.
        }
    }

    private static func legacyAndUnknownLayersRemainDecodableButNonProjectable() throws {
        let identifier = "33333333-3333-3333-3333-333333333333"
        let legacyJSON = """
        {
          "annotationIdentifier": "\(identifier)",
          "frame": {"identifier": "legacy-frame", "capturedAt": 0},
          "geometry": {"kind": "point", "center": {"x": 0.5, "y": 0.5}}
        }
        """
        let legacy = try JSONDecoder().decode(
            AnatomicalAnnotationRequest.self,
            from: Data(legacyJSON.utf8)
        )
        try require(
            legacy.targetLayer == .floating,
            "a request predating layer selection must default to floating"
        )

        let unknownJSON = legacyJSON.replacingOccurrences(
            of: "\"frame\":",
            with: "\"targetLayer\": \"futureLayer\", \"frame\":"
        )
        let unknown = try JSONDecoder().decode(
            AnatomicalAnnotationRequest.self,
            from: Data(unknownJSON.utf8)
        )
        try require(
            unknown.targetLayer == .floating,
            "unknown future layer values must decode to non-projectable floating"
        )
    }

    private static func clinicianGuidanceVersionRemainsUnchanged() throws {
        try require(
            ClinicianGuidanceProtocol.currentVersion == 1,
            "annotation transport must not version-bump stable clinician guidance"
        )
        let state = ClinicianGuidanceState.initial.settingFracturePosition(0.5)
        let message = ClinicianGuidanceMessage(
            sessionID: UUID(),
            sequence: 1,
            sentAt: Date(timeIntervalSince1970: 200),
            payload: .desiredGuidance(.set(state))
        )
        let data = try ClinicianGuidanceWireCodec.encode(message)
        try require(
            try ClinicianGuidanceWireCodec.decode(data) == message,
            "existing clinician-guidance messages must retain their round trip"
        )
    }

    private static func require(_ condition: Bool, _ message: String) throws {
        guard condition else { throw CheckFailure(message: message) }
    }
}

private struct CheckFailure: Error {
    let message: String
}
