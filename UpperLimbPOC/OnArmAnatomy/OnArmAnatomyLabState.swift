#if DEBUG
import Foundation
import OSLog
import simd

enum OnArmAnatomyFeatureGate {
    static let launchArgument = "--avp-on-arm-anatomy"

    static var isEnabled: Bool {
        ProcessInfo.processInfo.arguments.contains(launchArgument)
    }
}

enum OnArmAnatomyAssetPhase: Equatable {
    case idle
    case loading
    case ready(OnArmAnatomyAssetEvidence)
    case failed(String)
}

@MainActor
final class OnArmAnatomyLabState: ObservableObject {
    @Published private(set) var assetPhase: OnArmAnatomyAssetPhase = .idle
    @Published private(set) var currentPresentation: OnArmAnatomyPresentation?
    @Published private(set) var trackingRequested = false
    @Published private(set) var selectedVisibilityMode: OnArmAnatomyVisibilityMode = .normalOverlay
    @Published var calibration = OnArmAnatomyCalibration()

    private var presentationResolver = OnArmAnatomyPresentationResolver()
    private let logger = Logger(
        subsystem: "com.marcel.UpperLimbPOC",
        category: "OnArmAnatomy"
    )

    var canStartTracking: Bool {
        if case .ready = assetPhase { return !trackingRequested }
        return false
    }

    func prepareForOpening(_ visibilityMode: OnArmAnatomyVisibilityMode) {
        selectedVisibilityMode = visibilityMode
        assetPhase = .idle
        currentPresentation = nil
        trackingRequested = false
        calibration = OnArmAnatomyCalibration()
        presentationResolver.reset()
        logger.notice(
            "route=anatomyToolUSDZ mode=\(visibilityMode.rawValue, privacy: .public) state=prepare"
        )
    }

    func beginAssetLoad() {
        guard assetPhase == .idle else { return }
        assetPhase = .loading
        logger.notice("asset=hand-to-elbow-overlay state=loading")
    }

    func markAssetReady(_ evidence: OnArmAnatomyAssetEvidence) {
        assetPhase = .ready(evidence)
        logger.notice(
            "asset=hand-to-elbow-overlay state=static-ready bytes=\(evidence.assetByteCount) radiusZ=\(evidence.radiusExtentsMetres.z, format: .fixed(precision: 4)) ulnaZ=\(evidence.ulnaExtentsMetres.z, format: .fixed(precision: 4))"
        )
    }

    func markAssetFailed(_ detail: String) {
        assetPhase = .failed(detail)
        currentPresentation = nil
        logger.error("asset=hand-to-elbow-overlay state=failed detail=\(detail, privacy: .public)")
    }

    func requestRightForearmTracking() {
        guard canStartTracking else { return }
        trackingRequested = true
        logger.notice("tracking=right-only state=requested")
    }

    func resolvePresentation(
        resolution: AVPForearmOverlayResolution,
        wristTransform: simd_float4x4?,
        timestamp: Double
    ) -> OnArmAnatomyPresentation {
        let presentation = presentationResolver.resolve(
            resolution: resolution,
            wristTransform: wristTransform,
            trackingRequested: trackingRequested,
            calibration: calibration,
            timestamp: timestamp
        )
        if currentPresentation?.mode != presentation.mode {
            logger.notice(
                "tracking=right-only state=\(presentation.mode.rawValue, privacy: .public) visible=\(presentation.isVisible)"
            )
        }
        if currentPresentation != presentation {
            currentPresentation = presentation
        }
        return presentation
    }

    func reset() {
        assetPhase = .idle
        currentPresentation = nil
        trackingRequested = false
        calibration = OnArmAnatomyCalibration()
        presentationResolver.reset()
        logger.notice("state=reset")
    }
}
#endif
