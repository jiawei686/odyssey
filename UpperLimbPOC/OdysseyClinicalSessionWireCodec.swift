import Foundation

enum OdysseyClinicalSessionWireCodecError: Error, Equatable {
    case malformedMessage
    case unsupportedVersion(Int)
}

struct OdysseyClinicalSessionWireCodec: Sendable {
    private struct Header: Decodable {
        let protocolIdentifier: String?
    }

    func encode(_ message: OdysseyClinicalSessionMessage) throws -> Data {
        guard message.protocolVersion == OdysseyClinicalSessionProtocol.currentVersion else {
            throw OdysseyClinicalSessionWireCodecError.unsupportedVersion(
                message.protocolVersion
            )
        }
        guard message.isStructurallyValid else {
            throw OdysseyClinicalSessionWireCodecError.malformedMessage
        }

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .millisecondsSince1970
        encoder.outputFormatting = [.sortedKeys]
        return try encoder.encode(message)
    }

    func decode(_ data: Data) throws -> OdysseyClinicalSessionMessage {
        let decoder = makeDecoder()
        let message = try decoder.decode(OdysseyClinicalSessionMessage.self, from: data)
        guard message.protocolVersion == OdysseyClinicalSessionProtocol.currentVersion else {
            throw OdysseyClinicalSessionWireCodecError.unsupportedVersion(
                message.protocolVersion
            )
        }
        guard message.isStructurallyValid else {
            throw OdysseyClinicalSessionWireCodecError.malformedMessage
        }
        return message
    }

    /// Returns `nil` for packets owned by the existing guidance/snapshot wire
    /// families so a transport multiplexer can pass them to their legacy codec.
    /// Once this protocol identifier is present, malformed packets fail closed.
    func decodeIfOdysseyClinicalSession(
        _ data: Data
    ) throws -> OdysseyClinicalSessionMessage? {
        let decoder = makeDecoder()
        let header = try decoder.decode(Header.self, from: data)
        guard header.protocolIdentifier == OdysseyClinicalSessionProtocol.identifier else {
            return nil
        }
        return try decode(data)
    }

    private func makeDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .millisecondsSince1970
        return decoder
    }
}
