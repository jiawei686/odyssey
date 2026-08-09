#if DEBUG
import SwiftUI

enum CTForearmVRTFeatureGate {
    static let launchArgument = "--ct-forearm-vrt-preview"
    static var isEnabled: Bool { ProcessInfo.processInfo.arguments.contains(launchArgument) }
}

struct CTForearmVRTPreview: View {
    @State private var revealAnatomy: Double
    @State private var rendererID = UUID()

    init() {
        let startsAtBone = ProcessInfo.processInfo.arguments.contains("--ct-vrt-bone-preset")
        _revealAnatomy = State(initialValue: startsAtBone ? 1 : 0)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    VStack(alignment: .leading, spacing: 6) {
                        Label("DEBUG CT volume-rendering spike", systemImage: "cube.transparent")
                            .font(.title2.bold())
                        Text("NLM Visible Human reference anatomy — not wearer-specific imaging.")
                            .font(.callout.weight(.semibold))
                            .foregroundStyle(.orange)
                        Text("True 3D ray-marched CT subvolume. No DICOM, identifiers, or wearer pixels are loaded.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }

                    CTForearmVolumePanel(revealAnatomy: Float(revealAnatomy))
                        .id(rendererID)
                        .frame(maxWidth: .infinity)
                        .frame(height: 460)
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                        .overlay(RoundedRectangle(cornerRadius: 14).stroke(.white.opacity(0.16)))
                        .accessibilityLabel("Ray-marched reference CT forearm volume")
                        .accessibilityValue("Reveal anatomy \(Int((revealAnatomy * 100).rounded())) percent")

                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Button("Surface preset") { revealAnatomy = 0 }
                                .buttonStyle(.bordered)
                            Button("Bone preset") { revealAnatomy = 1 }
                                .buttonStyle(.bordered)
                            Spacer()
                            Text("\(Int((revealAnatomy * 100).rounded()))%")
                                .monospacedDigit()
                        }

                        Slider(value: $revealAnatomy, in: 0 ... 1) {
                            Text("Reveal Anatomy")
                        } minimumValueLabel: {
                            Text("Surface").font(.caption)
                        } maximumValueLabel: {
                            Text("Bone").font(.caption)
                        }
                        .accessibilityLabel("Reveal Anatomy")
                        .accessibilityValue("\(Int((revealAnatomy * 100).rounded())) percent")

                        Text("Reveal Anatomy continuously interpolates one CT transfer function from soft-tissue surface emphasis to bone emphasis.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }

                    Button {
                        rendererID = UUID()
                    } label: {
                        Label("Reload CT volume", systemImage: "arrow.clockwise")
                    }
                    .buttonStyle(.bordered)

                    Divider()
                    Text("Reference crop: NLM Visible Human Male normalCT, slices 1680–1740 at the 21 available 3 mm locations. The original CT field of view truncates part of the lateral forearm. Orientation and laterality are illustrative. This simulator view does not verify physical Apple Vision Pro performance, pose, comfort, or registration.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                .padding(24)
            }
            .navigationTitle("CT Forearm VRT")
        }
    }
}

#Preview("CT forearm VRT") { CTForearmVRTPreview() }
#endif
