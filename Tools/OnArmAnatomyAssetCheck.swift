import CryptoKit
import Foundation
import simd

@main
enum OnArmAnatomyAssetCheck {
    static func main() throws {
        guard CommandLine.arguments.count == 3 else {
            throw CheckError.failed("Usage: check <USDZ path> <usdcat USDA path>")
        }
        let assetURL = URL(fileURLWithPath: CommandLine.arguments[1])
        let usdaURL = URL(fileURLWithPath: CommandLine.arguments[2])
        let asset = try Data(contentsOf: assetURL)
        let hash = SHA256.hash(data: asset)
            .map { String(format: "%02x", $0) }
            .joined()
        try expect(
            hash == OnArmAnatomyAssetContract.assetSHA256,
            "unexpected USDZ SHA-256: \(hash)"
        )
        try expect(
            asset.count > 1_000_000 && asset.count < 3_000_000,
            "unexpected USDZ byte count: \(asset.count)"
        )

        let usda = try String(contentsOf: usdaURL, encoding: .utf8)
        try expect(usda.contains("metersPerUnit = 1"), "asset must use metres")
        try expect(usda.contains("upAxis = \"Z\""), "asset must be Z-up")

        let radius = try rootBounds(
            for: OnArmAnatomyAssetContract.radiusNodeName,
            in: usda
        )
        let ulna = try rootBounds(
            for: OnArmAnatomyAssetContract.ulnaNodeName,
            in: usda
        )
        try expect(
            OnArmAnatomyAssetContract.plausibleRadiusLength
                .contains(radius.extents.z),
            "Radius_r Z extent is not approximately 239.9 mm: \(radius.extents.z)"
        )
        try expect(
            OnArmAnatomyAssetContract.plausibleUlnaLength
                .contains(ulna.extents.z),
            "Ulna_r Z extent is not approximately 262.5 mm: \(ulna.extents.z)"
        )
        try expect(
            abs(ulna.extents.z - OnArmAnatomyAssetContract.referenceForearmLengthMetres)
                < 0.000_1,
            "ulna reference length must define scale normalization"
        )
        try expect(
            usda.contains("Proximal_phalanx_of_2d_finger_r"),
            "hand/finger meshes must remain present for the deferred rig"
        )
        print(
            "On-arm anatomy asset checks passed: "
                + "Radius \(radius.extents.z * 1_000) mm, "
                + "Ulna \(ulna.extents.z * 1_000) mm"
        )
    }

    private static func rootBounds(
        for nodeName: String,
        in usda: String
    ) throws -> (min: SIMD3<Float>, max: SIMD3<Float>, extents: SIMD3<Float>) {
        let marker = "    def Xform \"\(nodeName)\""
        guard let start = usda.range(of: marker) else {
            throw CheckError.failed("missing named Xform \(nodeName)")
        }
        let tailStart = start.upperBound
        let next = usda.range(
            of: "\n    def Xform \"",
            range: tailStart ..< usda.endIndex
        )?.lowerBound ?? usda.endIndex
        let block = String(usda[start.lowerBound ..< next])
        let translation = try firstTriple(
            pattern: #"double3 xformOp:translate = \(([^)]+)\)"#,
            in: block,
            context: "\(nodeName) translation"
        )
        let extentMatch = try firstMatch(
            pattern: #"float3\[\] extent = \[\(([^)]+)\), \(([^)]+)\)\]"#,
            in: block,
            context: "\(nodeName) extent"
        )
        let localMin = try triple(extentMatch[1])
        let localMax = try triple(extentMatch[2])
        let minimum = translation + localMin
        let maximum = translation + localMax
        return (minimum, maximum, maximum - minimum)
    }

    private static func firstTriple(
        pattern: String,
        in text: String,
        context: String
    ) throws -> SIMD3<Float> {
        let match = try firstMatch(pattern: pattern, in: text, context: context)
        return try triple(match[1])
    }

    private static func firstMatch(
        pattern: String,
        in text: String,
        context: String
    ) throws -> [String] {
        let expression = try NSRegularExpression(pattern: pattern)
        let fullRange = NSRange(text.startIndex..., in: text)
        guard let result = expression.firstMatch(in: text, range: fullRange) else {
            throw CheckError.failed("missing \(context)")
        }
        return (0 ..< result.numberOfRanges).map { index in
            guard let range = Range(result.range(at: index), in: text) else {
                return ""
            }
            return String(text[range])
        }
    }

    private static func triple(_ string: String) throws -> SIMD3<Float> {
        let values = string.split(separator: ",").compactMap {
            Float($0.trimmingCharacters(in: .whitespaces))
        }
        guard values.count == 3 else {
            throw CheckError.failed("invalid vector: \(string)")
        }
        return SIMD3<Float>(values[0], values[1], values[2])
    }

    private static func expect(
        _ condition: @autoclosure () -> Bool,
        _ message: String
    ) throws {
        guard condition() else { throw CheckError.failed(message) }
    }

    private enum CheckError: Error {
        case failed(String)
    }
}
