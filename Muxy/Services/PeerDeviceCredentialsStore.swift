import Foundation
import Security

struct PeerCredentials {
    let deviceID: UUID
    let token: String
}

enum PeerDeviceCredentialsStore {
    private static let service = "app.muxy.peer-client"

    static func load(host: String) -> PeerCredentials {
        if let existing = readFromKeychain(host: host) {
            return existing
        }
        let created = PeerCredentials(deviceID: UUID(), token: generateToken())
        writeToKeychain(created, host: host)
        return created
    }

    static func clear(host: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: host,
        ]
        SecItemDelete(query as CFDictionary)
    }

    private static func generateToken() -> String {
        var bytes = [UInt8](repeating: 0, count: 32)
        let status = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        if status == errSecSuccess {
            return Data(bytes).base64EncodedString()
        }
        return UUID().uuidString + UUID().uuidString
    }

    private static func readFromKeychain(host: String) -> PeerCredentials? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: host,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess,
              let data = item as? Data,
              let stored = try? JSONDecoder().decode(StoredCredentials.self, from: data)
        else { return nil }
        return PeerCredentials(deviceID: stored.deviceID, token: stored.token)
    }

    private static func writeToKeychain(_ credentials: PeerCredentials, host: String) {
        let stored = StoredCredentials(deviceID: credentials.deviceID, token: credentials.token)
        guard let data = try? JSONEncoder().encode(stored) else { return }
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: host,
        ]
        SecItemDelete(query as CFDictionary)
        var attributes = query
        attributes[kSecValueData as String] = data
        attributes[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        SecItemAdd(attributes as CFDictionary, nil)
    }

    private struct StoredCredentials: Codable {
        let deviceID: UUID
        let token: String
    }
}
