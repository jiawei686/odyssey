import Foundation

enum ClinicianGuidanceWireError: Error, Equatable {
    case invalidEnvelope
}

enum ClinicianGuidanceWireCodec {
    static func encode(_ message: ClinicianGuidanceMessage) throws -> Data {
        guard message.isStructurallyValid else {
            throw ClinicianGuidanceWireError.invalidEnvelope
        }
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .millisecondsSince1970
        encoder.outputFormatting = [.sortedKeys]
        return try encoder.encode(message)
    }

    static func decode(_ packet: Data) throws -> ClinicianGuidanceMessage {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .millisecondsSince1970
        let message = try decoder.decode(ClinicianGuidanceMessage.self, from: packet)
        guard message.isStructurallyValid else {
            throw ClinicianGuidanceWireError.invalidEnvelope
        }
        return message
    }
}
