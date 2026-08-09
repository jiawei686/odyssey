import SwiftUI

// Claude-owned companion presentation surface.
// The diagram consumes ClinicianGuidanceClientState and closure-based actions.

/// Names the coarse forearm zone for a normalized position where
/// 0 = proximal (elbow) and 1 = distal (wrist).
enum ClinicianForearmZone {
    static func name(for position: Double) -> String {
        switch position {
        case ..<(1.0 / 3.0): "proximal third"
        case ..<(2.0 / 3.0): "mid-shaft"
        default: "distal third"
        }
    }

    static func percentText(for position: Double) -> String {
        "\(Int((position * 100).rounded()))%"
    }

    static func displayName(for position: Double) -> String {
        let zoneName = name(for: position)
        return zoneName.prefix(1).uppercased() + zoneName.dropFirst()
    }
}

/// Simplified, illustrative forearm diagram. It is driven exclusively by the
/// AVP-confirmed applied guidance state; a desired-but-unacknowledged change
/// appears only as the pending badge, never as applied drawing. The diagram
/// makes no claim of spatial registration.
struct ClinicianForearmCanvas: View {
    let appliedState: ClinicianGuidanceAppliedState?
    let connectionStatus: ClinicianGuidanceConnectionStatus
    let isPendingAcknowledgment: Bool

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: 8) {
            diagram
                .frame(maxWidth: .infinity)
                .frame(minHeight: 170, maxHeight: 300)

            HStack {
                Text("Elbow")
                Spacer()
                Text("Wrist")
            }
            .font(.caption)
            .foregroundStyle(.secondary)

            Text(
                "Generic teaching model — not the patient's anatomy or imaging. "
                    + "Positions are approximate."
            )
                .font(.caption2)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Forearm guidance preview")
        .accessibilityValue(accessibilitySummary)
    }

    private var diagram: some View {
        ZStack {
            Canvas { context, size in
                draw(in: context, size: size)
            }

            if appliedState == nil {
                Text(placeholderMessage)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)
            }
        }
        .overlay(alignment: .topTrailing) {
            statusBadges
                .padding(8)
        }
    }

    // MARK: - Drawing

    private func draw(in context: GraphicsContext, size: CGSize) {
        let outer = CGRect(origin: .zero, size: size).insetBy(dx: 10, dy: 14)
        guard outer.width > 60, outer.height > 40 else { return }

        // Soft-tissue silhouette: always drawn, so hiding the bone never
        // collapses the diagram.
        let silhouette = Path(
            roundedRect: outer,
            cornerRadius: outer.height * 0.30
        )
        context.fill(silhouette, with: .color(silhouetteFill))
        context.stroke(
            silhouette,
            with: .color(silhouetteStroke),
            lineWidth: 1.5
        )

        guard let applied = appliedState else { return }

        let boneSpan = outer.insetBy(
            dx: outer.width * 0.07,
            dy: outer.height * 0.24
        )

        if applied.state.showBone {
            drawBone(in: context, band: upperBand(of: boneSpan))
            drawBone(in: context, band: lowerBand(of: boneSpan))
        }

        if let fracture = applied.state.fracturePosition {
            let markerX = boneSpan.minX + boneSpan.width * fracture.value

            if applied.state.showIncisionGuide {
                drawIncisionGuide(in: context, atX: markerX, within: outer)
            }

            drawFractureMarker(
                in: context,
                atX: markerX,
                within: outer,
                boneSpan: boneSpan,
                boneVisible: applied.state.showBone
            )
        }
    }

    private func upperBand(of span: CGRect) -> CGRect {
        CGRect(
            x: span.minX,
            y: span.minY,
            width: span.width,
            height: span.height * 0.40
        )
    }

    private func lowerBand(of span: CGRect) -> CGRect {
        CGRect(
            x: span.minX,
            y: span.maxY - span.height * 0.40,
            width: span.width,
            height: span.height * 0.40
        )
    }

    private func drawBone(in context: GraphicsContext, band: CGRect) {
        let shaftHeight = band.height * 0.62
        let shaft = CGRect(
            x: band.minX + band.height * 0.45,
            y: band.midY - shaftHeight / 2,
            width: band.width - band.height * 0.90,
            height: shaftHeight
        )

        var bone = Path(roundedRect: shaft, cornerRadius: shaftHeight / 2)
        let knobSize = band.height * 0.95
        bone.addEllipse(in: CGRect(
            x: band.minX,
            y: band.midY - knobSize / 2,
            width: knobSize,
            height: knobSize
        ))
        bone.addEllipse(in: CGRect(
            x: band.maxX - knobSize,
            y: band.midY - knobSize / 2,
            width: knobSize,
            height: knobSize
        ))

        context.fill(bone, with: .color(boneFill))
        context.stroke(bone, with: .color(boneStroke), lineWidth: 1)
    }

    private func drawFractureMarker(
        in context: GraphicsContext,
        atX markerX: CGFloat,
        within outer: CGRect,
        boneSpan: CGRect,
        boneVisible: Bool
    ) {
        // Jagged break line across the bone region. The zigzag shape keeps the
        // marker recognizable without relying on color alone.
        let top = boneVisible ? boneSpan.minY - 4 : outer.minY + outer.height * 0.18
        let bottom = boneVisible ? boneSpan.maxY + 4 : outer.maxY - outer.height * 0.18
        let segmentCount = 6
        let segmentHeight = (bottom - top) / CGFloat(segmentCount)

        var zigzag = Path()
        zigzag.move(to: CGPoint(x: markerX, y: top))
        for segment in 1...segmentCount {
            let offset: CGFloat = segment.isMultiple(of: 2) ? -5 : 5
            zigzag.addLine(to: CGPoint(
                x: markerX + (segment == segmentCount ? 0 : offset),
                y: top + segmentHeight * CGFloat(segment)
            ))
        }
        context.stroke(
            zigzag,
            with: .color(.red),
            style: StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round)
        )

        // Position chevron above the silhouette.
        var chevron = Path()
        chevron.move(to: CGPoint(x: markerX - 6, y: outer.minY - 10))
        chevron.addLine(to: CGPoint(x: markerX + 6, y: outer.minY - 10))
        chevron.addLine(to: CGPoint(x: markerX, y: outer.minY - 2))
        chevron.closeSubpath()
        context.fill(chevron, with: .color(.red))
    }

    private func drawIncisionGuide(
        in context: GraphicsContext,
        atX markerX: CGFloat,
        within outer: CGRect
    ) {
        var guide = Path()
        guide.move(to: CGPoint(x: markerX, y: outer.minY - 6))
        guide.addLine(to: CGPoint(x: markerX, y: outer.maxY + 6))
        context.stroke(
            guide,
            with: .color(.teal),
            style: StrokeStyle(lineWidth: 2, lineCap: .round, dash: [6, 4])
        )
    }

    private var silhouetteFill: Color {
        Color(.tertiarySystemFill)
    }

    private var silhouetteStroke: Color {
        Color(.systemGray3)
    }

    private var boneFill: Color {
        colorScheme == .dark ? Color(.systemGray2) : .white
    }

    private var boneStroke: Color {
        Color(.systemGray)
    }

    // MARK: - Badges

    @ViewBuilder
    private var statusBadges: some View {
        VStack(alignment: .trailing, spacing: 6) {
            if isPendingAcknowledgment {
                badge {
                    HStack(spacing: 5) {
                        if reduceMotion {
                            Image(systemName: "hourglass")
                        } else {
                            ProgressView()
                                .controlSize(.mini)
                        }
                        Text("Updating…")
                    }
                }
            }

            if showsLastConfirmedBadge {
                badge {
                    Label("Last confirmed state", systemImage: "clock")
                        .foregroundStyle(.orange)
                }
            }

            if let tracking = trackingBadgeText {
                badge {
                    Label(tracking, systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.orange)
                }
            }

            if let applied = appliedState,
               applied.applicationStatus == .partiallyApplied {
                badge {
                    Label("Partially applied", systemImage: "exclamationmark.circle")
                        .foregroundStyle(.orange)
                }
            }

            if let side = participantSideText {
                badge {
                    Text(side)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private func badge(@ViewBuilder content: () -> some View) -> some View {
        content()
            .font(.caption2)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Color(.systemBackground).opacity(0.92), in: Capsule())
            .overlay(Capsule().stroke(Color(.systemGray4), lineWidth: 0.5))
    }

    private var showsLastConfirmedBadge: Bool {
        guard appliedState != nil else { return false }
        switch connectionStatus {
        case .disconnected, .connecting, .stale, .error: return true
        case .connected, .syncing: return false
        }
    }

    private var trackingBadgeText: String? {
        switch appliedState?.trackingStatus {
        case .stale: "Tracking stale"
        case .unavailable: "Tracking unavailable"
        case .failed: "Tracking failed"
        case .live, nil: nil
        }
    }

    private var participantSideText: String? {
        switch appliedState?.participantSide {
        case .left: "Left forearm"
        case .right: "Right forearm"
        case .unknown, nil: nil
        }
    }

    private var placeholderMessage: String {
        switch connectionStatus {
        case .disconnected, .connecting:
            "Connect to Apple Vision Pro to see the patient's confirmed guidance."
        case .connected, .syncing, .stale, .error:
            "Waiting for the first confirmed state from Vision Pro."
        }
    }

    // MARK: - Accessibility

    private var accessibilitySummary: String {
        guard let applied = appliedState else {
            return placeholderMessage
        }

        var parts: [String] = []
        parts.append(applied.state.showBone ? "Bone visible" : "Bone hidden")

        if let fracture = applied.state.fracturePosition {
            parts.append(
                "Fracture marker at \(ClinicianForearmZone.name(for: fracture.value)), "
                    + "\(ClinicianForearmZone.percentText(for: fracture.value)) from the elbow"
            )
        } else {
            parts.append("No fracture marker")
        }

        parts.append(
            applied.state.showIncisionGuide
                ? "Incision guide shown"
                : "Incision guide hidden"
        )

        if let side = participantSideText {
            parts.append(side)
        }
        if let tracking = trackingBadgeText {
            parts.append(tracking)
        }
        if isPendingAcknowledgment {
            parts.append("Waiting for Vision Pro to confirm a change")
        }
        if showsLastConfirmedBadge {
            parts.append("Showing the last confirmed state")
        }

        return parts.joined(separator: ". ")
    }
}

#Preview("Applied guidance") {
    List {
        ClinicianForearmCanvas(
            appliedState: ClinicianGuidanceAppliedState(
                state: ClinicianGuidanceState(
                    showBone: true,
                    fracturePosition: ClinicianForearmPosition(clamping: 0.42),
                    showIncisionGuide: true
                ),
                participantSide: .right,
                trackingStatus: .live,
                applicationStatus: .applied,
                sourceMessageID: UUID(),
                sourceSequence: 4,
                detail: nil
            ),
            connectionStatus: .connected,
            isPendingAcknowledgment: false
        )
    }
}

#Preview("Bone hidden, pending") {
    List {
        ClinicianForearmCanvas(
            appliedState: ClinicianGuidanceAppliedState(
                state: ClinicianGuidanceState(
                    showBone: false,
                    fracturePosition: ClinicianForearmPosition(clamping: 0.75),
                    showIncisionGuide: false
                ),
                participantSide: .left,
                trackingStatus: .live,
                applicationStatus: .applied,
                sourceMessageID: UUID(),
                sourceSequence: 6,
                detail: nil
            ),
            connectionStatus: .syncing,
            isPendingAcknowledgment: true
        )
    }
}

#Preview("Disconnected, no applied state") {
    List {
        ClinicianForearmCanvas(
            appliedState: nil,
            connectionStatus: .disconnected,
            isPendingAcknowledgment: false
        )
    }
}
