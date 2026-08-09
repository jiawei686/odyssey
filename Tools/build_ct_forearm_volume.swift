import CoreGraphics
import CryptoKit
import Foundation
import ImageIO

private enum BuildError: Error, CustomStringConvertible {
    case usage
    case missingSource(URL)
    case unreadableImage(URL)
    case unexpectedImage(URL, width: Int, height: Int, bitsPerComponent: Int)
    case contextCreation(URL)

    var description: String {
        switch self {
        case .usage:
            return "Usage: swift Tools/build_ct_forearm_volume.swift <source-png-directory> <output-directory>"
        case .missingSource(let url):
            return "Missing source image: \(url.path)"
        case .unreadableImage(let url):
            return "Could not decode source image: \(url.path)"
        case .unexpectedImage(let url, let width, let height, let bitsPerComponent):
            return "Expected a 512x512 16-bit grayscale PNG, got \(width)x\(height) at \(bitsPerComponent) bits: \(url.path)"
        case .contextCreation(let url):
            return "Could not create a 16-bit grayscale decode context for \(url.path)"
        }
    }
}

private struct SourceRecord: Encodable { let index: Int; let filename: String; let sha256: String }
private struct Crop: Encodable { let x: Int; let y: Int; let width: Int; let height: Int }
private struct SpacingMillimetres: Encodable { let x: Double; let y: Double; let z: Double }
private struct VolumeManifest: Encodable {
    let schemaVersion: Int
    let assetFilename: String
    let assetSHA256: String
    let pixelFormat: String
    let dimensions: [Int]
    let spacingMillimetres: SpacingMillimetres
    let crop: Crop
    let sourceDataset: String
    let sourceDirectoryURL: String
    let sourceFilePattern: String
    let sourceSlices: [SourceRecord]
    let sourceEncoding: String
    let quantization: String
    let coordinateRootIdentifier: String
    let coordinateMapping: String
    let limitations: [String]
}

private let sourceWidth = 512
private let sourceHeight = 512
private let sourceBitsPerComponent = 16
private let crop = Crop(x: 0, y: 130, width: 112, height: 160)
private let sliceIndices = Array(stride(from: 1680, through: 1740, by: 3))
private let outputFilename = "visible-human-male-forearm-1680-1740.r8"
private let manifestFilename = "visible-human-male-forearm-1680-1740.json"

private func sha256(_ data: Data) -> String {
    SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
}

private func decodeSource(_ url: URL) throws -> ([UInt16], Data) {
    guard FileManager.default.fileExists(atPath: url.path) else { throw BuildError.missingSource(url) }
    let sourceData = try Data(contentsOf: url)
    guard let source = CGImageSourceCreateWithData(sourceData as CFData, nil),
          let image = CGImageSourceCreateImageAtIndex(source, 0, nil)
    else { throw BuildError.unreadableImage(url) }
    guard image.width == sourceWidth, image.height == sourceHeight,
          image.bitsPerComponent == sourceBitsPerComponent
    else {
        throw BuildError.unexpectedImage(url, width: image.width, height: image.height,
                                         bitsPerComponent: image.bitsPerComponent)
    }

    var pixels = [UInt16](repeating: 0, count: sourceWidth * sourceHeight)
    let created = pixels.withUnsafeMutableBytes { bytes -> Bool in
        guard let context = CGContext(
            data: bytes.baseAddress, width: sourceWidth, height: sourceHeight,
            bitsPerComponent: sourceBitsPerComponent,
            bytesPerRow: sourceWidth * MemoryLayout<UInt16>.size,
            space: CGColorSpaceCreateDeviceGray(),
            bitmapInfo: CGImageAlphaInfo.none.rawValue | CGBitmapInfo.byteOrder16Little.rawValue
        ) else { return false }
        context.interpolationQuality = .none
        context.draw(image, in: CGRect(x: 0, y: 0, width: sourceWidth, height: sourceHeight))
        return true
    }
    guard created else { throw BuildError.contextCreation(url) }
    return (pixels, sourceData)
}

private func quantize(_ sourceValue: UInt16) -> UInt8 {
    // NLM pixels are 12-bit values stored in 16-bit PNGs. Dividing by eight
    // retains 0...2040 in one GPU-ready R8 channel; rarer values saturate.
    UInt8(clamping: (Int(sourceValue) + 4) / 8)
}

private func run() throws {
    guard CommandLine.arguments.count == 3 else { throw BuildError.usage }
    let sourceDirectory = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
    let outputDirectory = URL(fileURLWithPath: CommandLine.arguments[2], isDirectory: true)
    try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)

    var volume = Data(capacity: crop.width * crop.height * sliceIndices.count)
    var records: [SourceRecord] = []
    for index in sliceIndices {
        let filename = "cvm\(index)f.png"
        let url = sourceDirectory.appendingPathComponent(filename)
        let (pixels, sourceData) = try decodeSource(url)
        records.append(SourceRecord(index: index, filename: filename, sha256: sha256(sourceData)))
        for y in crop.y ..< (crop.y + crop.height) {
            let rowStart = y * sourceWidth + crop.x
            for x in 0 ..< crop.width { volume.append(quantize(pixels[rowStart + x])) }
        }
    }

    let expectedByteCount = crop.width * crop.height * sliceIndices.count
    precondition(volume.count == expectedByteCount)
    let outputURL = outputDirectory.appendingPathComponent(outputFilename)
    try volume.write(to: outputURL, options: .atomic)

    let manifest = VolumeManifest(
        schemaVersion: 1,
        assetFilename: outputFilename,
        assetSHA256: sha256(volume),
        pixelFormat: "r8Unorm",
        dimensions: [crop.width, crop.height, sliceIndices.count],
        spacingMillimetres: SpacingMillimetres(x: 0.8984375, y: 0.8984375, z: 3.0),
        crop: crop,
        sourceDataset: "NLM Visible Human Male normalCT",
        sourceDirectoryURL: "https://data.lhncbc.nlm.nih.gov/public/Visible-Human/Male-Images/PNG_format/radiological/normalCT/",
        sourceFilePattern: "cvm{index}f.png",
        sourceSlices: records,
        sourceEncoding: "12-bit GE CT values stored in 16-bit grayscale PNG",
        quantization: "UInt8(clamp(round(sourceValue / 8), 0...255))",
        coordinateRootIdentifier: "GenericForearmCoordinateRoot",
        coordinateMapping: "texture +X -> forearm +X; texture +Y -> forearm -Z; increasing source index -> forearm +Y (proximal-to-distal illustrative axis)",
        limitations: [
            "Reference anatomy from one cadaver; not wearer-specific imaging.",
            "The original CT field of view truncates the lateral forearm surface in this crop.",
            "No A/P or R/L orientation claim is made.",
            "No physical Apple Vision Pro registration or rendering performance is verified by this asset build."
        ]
    )
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
    var manifestData = try encoder.encode(manifest)
    manifestData.append(0x0A)
    try manifestData.write(to: outputDirectory.appendingPathComponent(manifestFilename), options: .atomic)
    print("Wrote \(outputURL.path) (\(volume.count) bytes, sha256 \(sha256(volume)))")
}

do {
    try run()
} catch {
    FileHandle.standardError.write(Data("error: \(error)\n".utf8))
    exit(1)
}
