import SwiftUI
import SceneKit

struct CompanionContentView: View {
    @EnvironmentObject private var overlay: OverlayState
    @EnvironmentObject private var peer: PeerSession

    var body: some View {
        NavigationStack {
            HStack(spacing: 24) {
                USDZPreview(opacity: overlay.opacity)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(.black.opacity(0.05), in: RoundedRectangle(cornerRadius: 20))

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
                        control("Opacity", value: $overlay.opacity, range: 0.25...1.00, unit: "")
                    }
                    .disabled(overlay.locked)

                    HStack {
                        Button(overlay.locked ? "Unlock" : "Lock") {
                            overlay.locked.toggle()
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(overlay.locked ? .green : .blue)

                        Button("Reset", action: overlay.reset)

                        Button("Find model", action: overlay.makeVisible)
                    }

                    Text("Transforms only. Do not transmit patient images or identifiers.")
                        .font(.footnote)
                        .foregroundStyle(.orange)
                }
                .frame(maxWidth: 480)
            }
            .padding(24)
            .navigationTitle("Radiographic Companion")
        }
        .onAppear(perform: peer.start)
        .onChange(of: overlay.snapshot) { _, snapshot in
            peer.send(snapshot)
        }
        .onChange(of: peer.isConnected) { _, connected in
            if connected {
                peer.send(overlay.snapshot)
            }
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
            Slider(value: value, in: range)
            Text("\(value.wrappedValue, specifier: "%.2f")\(unit)")
                .monospacedDigit()
                .frame(width: 88, alignment: .trailing)
        }
    }
}

private struct USDZPreview: UIViewRepresentable {
    let opacity: Double

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
        applyOpacity(to: scene.rootNode)
        return view
    }

    func updateUIView(_ uiView: SCNView, context: Context) {
        guard let rootNode = uiView.scene?.rootNode else { return }
        applyOpacity(to: rootNode)
    }

    private func applyOpacity(to rootNode: SCNNode) {
        rootNode.enumerateChildNodes { node, _ in
            guard node.geometry != nil else { return }
            node.opacity = CGFloat(opacity)
        }
    }
}
