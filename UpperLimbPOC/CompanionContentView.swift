import SwiftUI
import SceneKit
import UIKit

struct CompanionContentView: View {
    @EnvironmentObject private var overlay: OverlayState
    @EnvironmentObject private var peer: PeerSession

    var body: some View {
        NavigationStack {
            HStack(spacing: 24) {
                USDZPreview(opacity: overlay.opacity, tint: overlay.tint)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(.black.opacity(0.05), in: RoundedRectangle(cornerRadius: 20))

                ScrollView {
                    VStack(spacing: 14) {
                        Label(
                            peer.status,
                            systemImage: peer.isConnected ? "vision.pro" : "network"
                        )
                        .foregroundStyle(peer.isConnected ? .green : .secondary)

                        Text("Remote calibration")
                            .font(.title2.bold())

                        Group {
                            control("Left / right", value: $overlay.x, range: -0.50...0.50, unit: "m")
                            control("Up / down", value: $overlay.y, range: -0.50...0.50, unit: "m")
                            control("Near / far", value: $overlay.z, range: -1.50 ... -0.20, unit: "m")
                            control("Pitch", value: $overlay.pitchDegrees, range: -180...180, unit: "°")
                            control("Yaw", value: $overlay.yawDegrees, range: -180...180, unit: "°")
                            control("Roll", value: $overlay.rollDegrees, range: -180...180, unit: "°")
                            control("Scale", value: $overlay.scale, range: 0.50...1.50, unit: "×")
                        }
                        .disabled(overlay.locked)

                        appearanceControls

                        Divider()

                        Group {
                            Toggle(
                                "Show reference axial section",
                                isOn: syncing($overlay.sectionVisible)
                            )
                            .font(.headline)

                            control(
                                "Slice position",
                                value: Binding(
                                    get: { overlay.normalizedSlicePosition },
                                    set: overlay.setSectionPosition
                                ),
                                range: 0...1,
                                unit: ""
                            )
                            .disabled(!overlay.sectionVisible)

                            HStack {
                                Stepper(
                                    value: Binding(
                                        get: { overlay.selectedSliceIndex },
                                        set: { index in
                                            overlay.selectSlice(index)
                                            sendCurrentState()
                                        }
                                    ),
                                    in: 0...(overlay.sliceCount - 1)
                                ) {
                                    Text("Reference slice")
                                }

                                Spacer()

                                Text("\(overlay.selectedSliceIndex + 1) / \(overlay.sliceCount)")
                                    .monospacedDigit()
                            }
                            .disabled(!overlay.sectionVisible)

                            control(
                                "Slice opacity",
                                value: $overlay.sectionOpacity,
                                range: 0.15...1.0,
                                unit: ""
                            )
                            .disabled(!overlay.sectionVisible)
                        }

                        HStack {
                            Button(overlay.locked ? "Unlock" : "Lock") {
                                overlay.locked.toggle()
                                sendCurrentState()
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(overlay.locked ? .green : .blue)

                            Button("Reset") {
                                overlay.reset()
                                sendCurrentState()
                            }

                            Button("Find model") {
                                overlay.makeVisible()
                                sendCurrentState()
                            }
                        }

                        Text("NLM reference CT is cross-subject and approximate. Do not transmit patient images or identifiers.")
                            .font(.footnote)
                            .foregroundStyle(.orange)

                        Text("Axial orientation and laterality are illustrative only; A/P and R/L are not registered in this prototype.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(maxWidth: 480)
            }
            .padding(24)
            .navigationTitle("Radiographic Companion")
        }
        .onAppear(perform: peer.start)
        .onReceive(peer.$lastSnapshot.compactMap { $0 }) { snapshot in
            overlay.applyCalibration(snapshot)
        }
    }

    @ViewBuilder
    private var appearanceControls: some View {
        VStack(spacing: 10) {
            HStack {
                Text("Bone opacity")
                    .frame(width: 110, alignment: .leading)
                Slider(value: syncing($overlay.opacity), in: 0.25...1.00)
                HStack(spacing: 5) {
                    Button {
                        adjustOpacity(by: -0.05)
                    } label: {
                        Image(systemName: "minus")
                    }
                    .accessibilityLabel("Decrease bone opacity")
                    .disabled(overlay.opacity <= 0.25)

                    Text("\(Int((overlay.opacity * 100).rounded()))%")
                        .monospacedDigit()
                        .frame(width: 42)

                    Button {
                        adjustOpacity(by: 0.05)
                    } label: {
                        Image(systemName: "plus")
                    }
                    .accessibilityLabel("Increase bone opacity")
                    .disabled(overlay.opacity >= 1.00)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .fixedSize()
            }

            HStack {
                Text("Bone colour")
                    .frame(width: 110, alignment: .leading)

                Picker("Bone colour", selection: syncing($overlay.tint)) {
                    ForEach(OverlayTint.allCases) { tint in
                        Text(tint.name).tag(tint)
                    }
                }
                .pickerStyle(.menu)

                Spacer()

                Circle()
                    .fill(swiftUIColor(for: overlay.tint))
                    .frame(width: 24, height: 24)
                    .overlay(Circle().stroke(.secondary, lineWidth: 1))

                Text(overlay.tint.name)
                    .frame(width: 58, alignment: .trailing)
            }

            Text("Lower opacity makes the bone overlay more translucent.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    @ViewBuilder
    private func control(
        _ title: String,
        value: Binding<Double>,
        range: ClosedRange<Double>,
        unit: String
    ) -> some View {
        HStack {
            Text(title).frame(width: 110, alignment: .leading)
            Slider(value: syncing(value), in: range)
            Text("\(value.wrappedValue, specifier: "%.2f")\(unit)")
                .monospacedDigit()
                .frame(width: 88, alignment: .trailing)
        }
    }

    private func syncing<Value>(_ binding: Binding<Value>) -> Binding<Value> {
        Binding(
            get: { binding.wrappedValue },
            set: { newValue in
                binding.wrappedValue = newValue
                sendCurrentState()
            }
        )
    }

    private func sendCurrentState() {
        peer.send(overlay.snapshot)
    }

    private func adjustOpacity(by delta: Double) {
        let stepped = ((overlay.opacity + delta) * 20).rounded() / 20
        overlay.opacity = min(1.00, max(0.25, stepped))
        sendCurrentState()
    }

    private func swiftUIColor(for tint: OverlayTint) -> Color {
        let rgb = tint.rgb
        return Color(red: rgb.red, green: rgb.green, blue: rgb.blue)
    }
}

private struct USDZPreview: UIViewRepresentable {
    let opacity: Double
    let tint: OverlayTint

    func makeUIView(context: Context) -> SCNView {
        let view = SCNView()
        view.backgroundColor = .secondarySystemBackground
        view.autoenablesDefaultLighting = true
        view.allowsCameraControl = true
        view.antialiasingMode = .multisampling4X

        guard let url = Bundle.main.url(
            forResource: "hand-to-elbow-overlay",
            withExtension: "usdz"
        ), let scene = try? SCNScene(url: url) else {
            return view
        }

        let cameraNode = SCNNode()
        cameraNode.camera = SCNCamera()
        cameraNode.camera?.zNear = 0.01
        cameraNode.camera?.zFar = 10.0
        cameraNode.position = SCNVector3(0, -0.75, 0)
        cameraNode.eulerAngles = SCNVector3(Float.pi / 2, 0, 0)
        scene.rootNode.addChildNode(cameraNode)

        view.scene = scene
        view.pointOfView = cameraNode
        view.defaultCameraController.interactionMode = .orbitTurntable
        applyAppearance(to: scene.rootNode)
        return view
    }

    func updateUIView(_ uiView: SCNView, context: Context) {
        guard let rootNode = uiView.scene?.rootNode else { return }
        applyAppearance(to: rootNode)
    }

    private func applyAppearance(to rootNode: SCNNode) {
        let rgb = tint.rgb
        let color = UIColor(
            red: rgb.red,
            green: rgb.green,
            blue: rgb.blue,
            alpha: 1.0
        )
        rootNode.enumerateChildNodes { node, _ in
            guard let geometry = node.geometry else { return }
            node.opacity = CGFloat(opacity)
            geometry.materials.forEach { material in
                material.diffuse.contents = color
            }
        }
    }
}
