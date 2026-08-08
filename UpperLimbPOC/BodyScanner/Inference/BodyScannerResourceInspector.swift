import CryptoKit
import Foundation

enum BodyScannerResourceInspector {
    static func fingerprint(of fileURL: URL) throws -> BodyScannerResourceFingerprint {
        let data = try Data(contentsOf: fileURL, options: [.mappedIfSafe, .uncached])
        let digest = SHA256.hash(data: data)
        let sha256 = digest.map { String(format: "%02x", $0) }.joined()
        return BodyScannerResourceFingerprint(sha256: sha256, byteCount: data.count)
    }
}
