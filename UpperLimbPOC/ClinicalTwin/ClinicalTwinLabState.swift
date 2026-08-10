#if DEBUG
import Foundation
import OSLog
import simd

enum ClinicalTwinLabFeatureGate {
    static let launchArgument = "--odyssey-clinical-twin"

    static var isEnabled: Bool {
        ProcessInfo.processInfo.arguments.contains(launchArgument)
    }
}

enum ClinicalTwinRendererPhase: Equatable {
    case idle
    case loading
    case staticReady(ClinicalTwinRenderEvidence)
    case failed(String)
}

struct ClinicalTwinRenderEvidence: Equatable {
    let assetByteCount: Int
    let radiusLengthMetres: Float
    let ulnaLengthMetres: Float
}

@MainActor
final class ClinicalTwinLabState: ObservableObject {
    @Published private(set) var rendererPhase: ClinicalTwinRendererPhase = .idle
    @Published private(set) var currentPresentation: ClinicalTwinPresentation?
    @Published private(set) var trackingRequested = false
    // Self-guided sessions start with the full Blender asset visible. A
    // negotiated companion reveal request may fade its opacity toward zero.
    @Published var revealAnatomy = 1.0

    private var presentationResolver = ClinicalTwinPresentationResolver()
    private let logger = Logger(
        subsystem: "com.marcel.UpperLimbPOC",
        category: "ClinicalTwin"
    )

    var canAttachToRightForearm: Bool {
        if case .staticReady = rendererPhase { return !trackingRequested }
        return false
    }

    func beginStaticSession() {
        guard rendererPhase == .idle else { return }
        rendererPhase = .loading
        logger.notice("route=anatomyToolBlenderUSDZ state=loading-static-reference")
    }

    func markStaticReady(_ evidence: ClinicalTwinRenderEvidence) {
        rendererPhase = .staticReady(evidence)
        logger.notice(
            "route=anatomyToolBlenderUSDZ state=static-ready bytes=\(evidence.assetByteCount) radiusMetres=\(evidence.radiusLengthMetres, format: .fixed(precision: 4)) ulnaMetres=\(evidence.ulnaLengthMetres, format: .fixed(precision: 4))"
        )
    }

    func markRendererFailed(_ detail: String) {
        rendererPhase = .failed(detail)
        currentPresentation = nil
        logger.error("route=anatomyToolBlenderUSDZ state=failed detail=\(detail, privacy: .public)")
    }

    func startRightForearmTracking(
        using tracking: LandmarkTrackingService
    ) async {
        guard canAttachToRightForearm else {
            logger.notice("tracking=right-only startup=ignored reason=not-ready-or-already-requested")
            return
        }
        trackingRequested = true
        logger.notice("tracking=right-only startup=requested renderer=static-ready")
        await tracking.startHandJointProbe()
        logger.notice(
            "tracking=right-only startup=completed provider=\(tracking.handPhase.message, privacy: .public) generation=\(tracking.handTrackingGeneration)"
        )
    }

    func resolvePresentation(
        resolution: AVPForearmOverlayResolution,
        wristTransform: simd_float4x4?,
        timestamp: Double
    ) -> ClinicalTwinPresentation {
        let presentation = presentationResolver.resolve(
            resolution: resolution,
            wristTransform: wristTransform,
            timestamp: timestamp
        )
        if currentPresentation?.mode != presentation.mode
            || currentPresentation?.statusTitle != presentation.statusTitle {
            logger.notice(
                "tracking=right-only state=\(presentation.mode.rawValue, privacy: .public) status=\(presentation.statusTitle, privacy: .public)"
            )
        }
        if currentPresentation != presentation {
            currentPresentation = presentation
        }
        return presentation
    }

    func reset() {
        rendererPhase = .idle
        currentPresentation = nil
        trackingRequested = false
        revealAnatomy = 1
        presentationResolver = ClinicalTwinPresentationResolver()
        logger.notice("state=reset")
    }
}
#endif
