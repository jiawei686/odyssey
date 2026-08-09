import Foundation

enum AnatomicalAnnotationWireCodecError: Error, Equatable {
    case malformedMessage
    case unsupportedVersion(Int)
}

struct AnatomicalAnnotationWireCodec: Sendable {
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    init() {
        encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .millisecondsSince1970
        encoder.outputFormatting = [.sortedKeys]

        decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .millisecondsSince1970
    }

    func encode(_ message: AnatomicalAnnotationWireMessage) throws -> Data {
        guard message.protocolVersion == AnatomicalAnnotationProtocol.currentVersion else {
            throw AnatomicalAnnotationWireCodecError.unsupportedVersion(message.protocolVersion)
        }
        guard message.isStructurallyValid else {
            throw AnatomicalAnnotationWireCodecError.malformedMessage
        }
        return try encoder.encode(message)
    }

    func decode(_ data: Data) throws -> AnatomicalAnnotationWireMessage {
        let message = try decoder.decode(AnatomicalAnnotationWireMessage.self, from: data)
        guard message.protocolVersion == AnatomicalAnnotationProtocol.currentVersion else {
            throw AnatomicalAnnotationWireCodecError.unsupportedVersion(message.protocolVersion)
        }
        guard message.isStructurallyValid else {
            throw AnatomicalAnnotationWireCodecError.malformedMessage
        }
        return message
    }
}
