import Foundation

enum UpperLimbPeerMessageType: String, Codable, Sendable {
    case jointFrame
}

struct UpperLimbPeerEnvelope: Codable, Equatable, Sendable {
    static let currentSchemaVersion = 1

    let schemaVersion: Int
    let messageType: UpperLimbPeerMessageType
    let jointFrame: UpperLimbJointFrame

    init(
        schemaVersion: Int = Self.currentSchemaVersion,
        jointFrame: UpperLimbJointFrame
    ) {
        self.schemaVersion = schemaVersion
        self.messageType = .jointFrame
        self.jointFrame = jointFrame
    }

    var isSupported: Bool {
        schemaVersion == Self.currentSchemaVersion
            && messageType == .jointFrame
            && jointFrame.isTruthful
    }
}
