#if DEBUG
import MetalKit
import SwiftUI
import simd

@MainActor
final class CTVolumeRendererTelemetry: ObservableObject {
    @Published private(set) var status = "Loading CT volume…"
    @Published private(set) var loadMilliseconds: Double?
    @Published private(set) var averageFrameMilliseconds: Double?
    @Published private(set) var measuredFrameCount = 0

    let logicalTexturePayloadBytes = CTForearmVolumeAsset.expectedByteCount
    var inferredPeakPayloadBytes: Int { logicalTexturePayloadBytes * 2 }

    func recordLoaded(milliseconds: Double) {
        loadMilliseconds = milliseconds
        status = "NLM CT volume loaded"
#if targetEnvironment(simulator)
        UserDefaults.standard.set(milliseconds, forKey: "CTVRTLoadMilliseconds")
        UserDefaults.standard.set(logicalTexturePayloadBytes, forKey: "CTVRTTextureBytes")
        _ = UserDefaults.standard.synchronize()
#endif
    }

    func recordFailure(_ message: String) { status = "CT VRT unavailable: \(message)" }

    func recordCompletedFrame(milliseconds: Double) {
        measuredFrameCount += 1
        let previous = averageFrameMilliseconds ?? milliseconds
        averageFrameMilliseconds = previous * 0.9 + milliseconds * 0.1
#if targetEnvironment(simulator)
        if measuredFrameCount.isMultiple(of: 15), let averageFrameMilliseconds {
            UserDefaults.standard.set(averageFrameMilliseconds, forKey: "CTVRTFrameMilliseconds")
            UserDefaults.standard.set(measuredFrameCount, forKey: "CTVRTFrameCount")
            _ = UserDefaults.standard.synchronize()
        }
#endif
    }
}

struct CTForearmVolumePanel: View {
    let revealAnatomy: Float
    @StateObject private var telemetry = CTVolumeRendererTelemetry()

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            CTForearmVolumeRendererView(revealAnatomy: revealAnatomy, telemetry: telemetry)
            VStack(alignment: .leading, spacing: 2) {
                Text(telemetry.status)
                if let load = telemetry.loadMilliseconds {
                    Text(String(format: "Renderer setup/load/upload %.1f ms · R8 payload %.0f KiB", load,
                                Double(telemetry.logicalTexturePayloadBytes) / 1024))
                }
                if let frame = telemetry.averageFrameMilliseconds {
                    Text(String(format: "Smoothed command completion %.1f ms · n=%d",
                                frame, telemetry.measuredFrameCount))
                }
                Text(String(format: "Peak R8 payload copies ≈ %.0f KiB (inferred)",
                            Double(telemetry.inferredPeakPayloadBytes) / 1024))
            }
            .font(.caption2.monospacedDigit())
            .padding(7)
            .background(.black.opacity(0.62), in: RoundedRectangle(cornerRadius: 6))
            .foregroundStyle(.white)
            .padding(8)
        }
        .allowsHitTesting(false)
    }
}

private struct CTVolumeUniforms {
    var inverseRotation: matrix_float4x4
    var volumeScaleAndReveal: SIMD4<Float>
    var viewportAndTime: SIMD4<Float>
}

struct CTForearmVolumeRendererView: UIViewRepresentable {
    let revealAnatomy: Float
    let telemetry: CTVolumeRendererTelemetry

    func makeCoordinator() -> Coordinator { Coordinator(telemetry: telemetry) }

    func makeUIView(context: Context) -> MTKView {
        let view = MTKView(frame: .zero, device: MTLCreateSystemDefaultDevice())
        view.colorPixelFormat = .bgra8Unorm_srgb
        view.clearColor = MTLClearColorMake(0.015, 0.02, 0.03, 1)
        view.preferredFramesPerSecond = 60
        view.enableSetNeedsDisplay = false
        view.isPaused = false
        context.coordinator.configure(view)
        view.delegate = context.coordinator
        return view
    }

    func updateUIView(_ view: MTKView, context: Context) {
        context.coordinator.revealAnatomy = min(max(revealAnatomy, 0), 1)
    }

    final class Coordinator: NSObject, MTKViewDelegate {
        private let telemetry: CTVolumeRendererTelemetry
        private var commandQueue: MTLCommandQueue?
        private var pipeline: MTLRenderPipelineState?
        private var volumeTexture: MTLTexture?
        private var startTime = CFAbsoluteTimeGetCurrent()
        var revealAnatomy: Float = 0

        init(telemetry: CTVolumeRendererTelemetry) { self.telemetry = telemetry }

        func configure(_ view: MTKView) {
            let loadStart = CFAbsoluteTimeGetCurrent()
            do {
                guard let device = view.device else { throw RendererError.noMetalDevice }
                guard let library = device.makeDefaultLibrary(),
                      let vertex = library.makeFunction(name: "ctVolumeVertex"),
                      let fragment = library.makeFunction(name: "ctVolumeFragment")
                else { throw RendererError.missingShader }
                let descriptor = MTLRenderPipelineDescriptor()
                descriptor.vertexFunction = vertex
                descriptor.fragmentFunction = fragment
                descriptor.colorAttachments[0].pixelFormat = view.colorPixelFormat
                pipeline = try device.makeRenderPipelineState(descriptor: descriptor)
                commandQueue = device.makeCommandQueue()
                volumeTexture = try makeTexture(device: device)
                startTime = CFAbsoluteTimeGetCurrent()
                let loadMilliseconds = (startTime - loadStart) * 1_000
                Task { @MainActor [telemetry] in
                    telemetry.recordLoaded(milliseconds: loadMilliseconds)
                }
            } catch {
                let message = String(describing: error)
                Task { @MainActor [telemetry] in
                    telemetry.recordFailure(message)
                }
            }
        }

        private func makeTexture(device: MTLDevice) throws -> MTLTexture {
            let volume = try CTForearmVolumeData.load()
            let descriptor = MTLTextureDescriptor()
            descriptor.textureType = .type3D
            descriptor.pixelFormat = .r8Unorm
            descriptor.width = volume.dimensions.x
            descriptor.height = volume.dimensions.y
            descriptor.depth = volume.dimensions.z
            descriptor.mipmapLevelCount = 1
            descriptor.usage = .shaderRead
            descriptor.storageMode = .shared
            guard let texture = device.makeTexture(descriptor: descriptor) else {
                throw RendererError.textureCreation
            }
            try volume.bytes.withUnsafeBytes { bytes in
                guard let baseAddress = bytes.baseAddress else { throw RendererError.emptyAsset }
                texture.replace(
                    region: MTLRegionMake3D(0, 0, 0, volume.dimensions.x,
                                            volume.dimensions.y, volume.dimensions.z),
                    mipmapLevel: 0,
                    slice: 0,
                    withBytes: baseAddress,
                    bytesPerRow: volume.dimensions.x,
                    bytesPerImage: volume.dimensions.x * volume.dimensions.y
                )
            }
            return texture
        }

        func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {}

        func draw(in view: MTKView) {
            guard let pipeline, let commandQueue, let volumeTexture,
                  let pass = view.currentRenderPassDescriptor,
                  let drawable = view.currentDrawable,
                  let commandBuffer = commandQueue.makeCommandBuffer(),
                  let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: pass)
            else { return }

            let physical = CTForearmVolumeAsset.physicalSizeMetres
            let longest = max(physical.x, max(physical.y, physical.z))
            let scale = physical / longest
            let elapsed = Float(CFAbsoluteTimeGetCurrent() - startTime)
            let displayRotation = rotationY(0.62 + sin(elapsed * 0.18) * 0.10)
                * rotationX(-0.28)
            let ctToForearmBasis = rotationX(-.pi / 2)
            let objectRotation = displayRotation * ctToForearmBasis
            var uniforms = CTVolumeUniforms(
                inverseRotation: objectRotation.transpose,
                volumeScaleAndReveal: SIMD4<Float>(scale, revealAnatomy),
                viewportAndTime: SIMD4<Float>(
                    Float(view.drawableSize.width / max(view.drawableSize.height, 1)),
                    elapsed, 0, 0
                )
            )

            encoder.setRenderPipelineState(pipeline)
            encoder.setFragmentBytes(&uniforms, length: MemoryLayout<CTVolumeUniforms>.stride, index: 0)
            encoder.setFragmentTexture(volumeTexture, index: 0)
            encoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
            encoder.endEncoding()
            commandBuffer.present(drawable)

            let submittedAt = CFAbsoluteTimeGetCurrent()
            let telemetry = self.telemetry
            commandBuffer.addCompletedHandler { [weak telemetry] _ in
                let milliseconds = (CFAbsoluteTimeGetCurrent() - submittedAt) * 1_000
                DispatchQueue.main.async {
                    telemetry?.recordCompletedFrame(milliseconds: milliseconds)
                }
            }
            commandBuffer.commit()
        }

        private func rotationX(_ angle: Float) -> matrix_float4x4 {
            matrix_float4x4(
                SIMD4<Float>(1, 0, 0, 0),
                SIMD4<Float>(0, cos(angle), sin(angle), 0),
                SIMD4<Float>(0, -sin(angle), cos(angle), 0),
                SIMD4<Float>(0, 0, 0, 1)
            )
        }

        private func rotationY(_ angle: Float) -> matrix_float4x4 {
            matrix_float4x4(
                SIMD4<Float>(cos(angle), 0, -sin(angle), 0),
                SIMD4<Float>(0, 1, 0, 0),
                SIMD4<Float>(sin(angle), 0, cos(angle), 0),
                SIMD4<Float>(0, 0, 0, 1)
            )
        }
    }

    private enum RendererError: Error {
        case noMetalDevice
        case missingShader
        case textureCreation
        case emptyAsset
    }
}
#endif
