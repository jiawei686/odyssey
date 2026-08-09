import Foundation
import Security

struct MedicalAssistantConfiguration: Sendable {
    static let live = MedicalAssistantConfiguration(
        baseURL: URL(string: "https://api.xcode.best/v1/")!,
        model: "gpt-5.4",
        requestTimeout: 75
    )

    let baseURL: URL
    let model: String
    let requestTimeout: TimeInterval

    var chatCompletionsURL: URL {
        baseURL.appendingPathComponent("chat/completions")
    }
}

enum AssistantCredentialError: LocalizedError {
    case emptyKey
    case keychain(OSStatus)

    var errorDescription: String? {
        switch self {
        case .emptyKey:
            "Enter an API key."
        case let .keychain(status):
            "The API key could not be stored securely (Keychain status \(status))."
        }
    }
}

struct AssistantCredentialStore: Sendable {
    private let service = "com.marcel.UpperLimbPOC.medical-assistant"
    private let account = "api.xcode.best"

    func loadAPIKey() throws -> String? {
        var query = baseQuery
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess else {
            throw AssistantCredentialError.keychain(status)
        }
        guard let data = result as? Data,
              let value = String(data: data, encoding: .utf8),
              !value.isEmpty
        else {
            return nil
        }
        return value
    }

    func saveAPIKey(_ rawValue: String) throws {
        let value = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { throw AssistantCredentialError.emptyKey }

        let data = Data(value.utf8)
        let updateStatus = SecItemUpdate(
            baseQuery as CFDictionary,
            [kSecValueData as String: data] as CFDictionary
        )
        if updateStatus == errSecSuccess { return }
        guard updateStatus == errSecItemNotFound else {
            throw AssistantCredentialError.keychain(updateStatus)
        }

        var addQuery = baseQuery
        addQuery[kSecValueData as String] = data
        addQuery[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        let addStatus = SecItemAdd(addQuery as CFDictionary, nil)
        guard addStatus == errSecSuccess else {
            throw AssistantCredentialError.keychain(addStatus)
        }
    }

    func deleteAPIKey() throws {
        let status = SecItemDelete(baseQuery as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw AssistantCredentialError.keychain(status)
        }
    }

    private var baseQuery: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
    }
}
