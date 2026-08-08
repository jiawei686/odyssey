import Foundation

@main
struct HybridLandmarkRegistrationCheck {
    static func main() throws {
        try checkProviderReadiness()
        try checkSimilaritySolution()
        try checkDegenerateFrameIsRejected()
        print("Hybrid landmark registration checks passed")
    }

    private static func checkProviderReadiness() throws {
        let model = reviewedModel()
        let axisObservations = [
            observation(.elbowReference, point: .zero, source: .imageMarker),
            observation(
                .wristCenter,
                point: LandmarkVector3(x: 0, y: 1, z: 0),
                source: .handSkeleton
            ),
            observation(
                .distalRadius,
                point: LandmarkVector3(x: 0.1, y: 1, z: 0),
                source: .sceneReconstructionSurface
            )
        ]

        let axisAssessment = HybridLandmarkRegistration.assess(
            model: model + [
                ModelRegistrationLandmark(
                    id: .wristCenter,
                    position: LandmarkVector3(x: 0, y: 1, z: 0),
                    humanReviewed: true
                )
            ],
            observed: axisObservations
        )
        try require(axisAssessment.readiness == .axisOnly, "two named joints should produce axis-only readiness")
        try require(axisAssessment.rejectedIDs.contains(.distalRadius), "scene mesh must not identify a named joint")

        let fullAssessment = HybridLandmarkRegistration.assess(
            model: model,
            observed: transformedObservations()
        )
        try require(fullAssessment.readiness == .fullFrame, "three reviewed non-collinear joints should produce full-frame readiness")
    }

    private static func checkSimilaritySolution() throws {
        let model = reviewedModel()
        let solution = try HybridLandmarkRegistration.solveForearmFrame(
            model: model,
            observed: transformedObservations()
        )

        try require(abs(solution.transform.scale - 2) < 1e-9, "uniform scale should be recovered")
        try require(solution.maximumResidualMillimetres < 1e-6, "known transform should have negligible residual")

        for landmark in model {
            let expected = knownTransform(landmark.position)
            let actual = solution.transform.applying(to: landmark.position)
            try require((actual - expected).length < 1e-9, "landmark transform mismatch for \(landmark.id.rawValue)")
        }
    }

    private static func checkDegenerateFrameIsRejected() throws {
        let collinear = [
            reviewed(.elbowReference, .zero),
            reviewed(.distalRadius, LandmarkVector3(x: 0, y: 1, z: 0)),
            reviewed(.distalUlna, LandmarkVector3(x: 0, y: 2, z: 0))
        ]
        let observations = collinear.map {
            observation($0.id, point: knownTransform($0.position), source: .manualHumanPlacement)
        }

        do {
            _ = try HybridLandmarkRegistration.solveForearmFrame(
                model: collinear,
                observed: observations
            )
            throw CheckFailure(message: "collinear landmarks must be rejected")
        } catch HybridLandmarkRegistrationError.degenerateLandmarkFrame {
            // Expected.
        }
    }

    private static func reviewedModel() -> [ModelRegistrationLandmark] {
        [
            reviewed(.elbowReference, .zero),
            reviewed(.distalRadius, LandmarkVector3(x: 0.1, y: 1, z: 0)),
            reviewed(.distalUlna, LandmarkVector3(x: -0.1, y: 1, z: 0))
        ]
    }

    private static func transformedObservations() -> [ObservedRegistrationLandmark] {
        reviewedModel().map {
            observation($0.id, point: knownTransform($0.position), source: .manualHumanPlacement)
        }
    }

    private static func knownTransform(_ point: LandmarkVector3) -> LandmarkVector3 {
        // Scale 2, rotate +90 degrees around Z, then translate.
        LandmarkVector3(
            x: -2 * point.y + 1,
            y: 2 * point.x - 2,
            z: 2 * point.z + 0.5
        )
    }

    private static func reviewed(
        _ id: RegistrationLandmarkID,
        _ point: LandmarkVector3
    ) -> ModelRegistrationLandmark {
        ModelRegistrationLandmark(id: id, position: point, humanReviewed: true)
    }

    private static func observation(
        _ id: RegistrationLandmarkID,
        point: LandmarkVector3,
        source: LandmarkObservationSource
    ) -> ObservedRegistrationLandmark {
        ObservedRegistrationLandmark(
            id: id,
            position: point,
            source: source,
            isTracked: true,
            confidence: nil
        )
    }

    private static func require(_ condition: Bool, _ message: String) throws {
        guard condition else { throw CheckFailure(message: message) }
    }
}

private struct CheckFailure: Error {
    let message: String
}
