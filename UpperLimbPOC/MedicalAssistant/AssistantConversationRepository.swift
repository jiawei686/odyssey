import Foundation

actor AssistantConversationRepository {
    private let fileName = "medical-assistant-conversation.json"

    func load() throws -> AssistantConversationSnapshot? {
        let url = try storageURL()
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        return try JSONDecoder().decode(
            AssistantConversationSnapshot.self,
            from: Data(contentsOf: url)
        )
    }

    func save(_ snapshot: AssistantConversationSnapshot) throws {
        let url = try storageURL()
        let directory = url.deletingLastPathComponent()
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        let data = try JSONEncoder().encode(snapshot)
        try data.write(to: url, options: [.atomic, .completeFileProtection])
    }

    func delete() throws {
        let url = try storageURL()
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        try FileManager.default.removeItem(at: url)
    }

    private func storageURL() throws -> URL {
        try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        ).appendingPathComponent(fileName, isDirectory: false)
    }
}
