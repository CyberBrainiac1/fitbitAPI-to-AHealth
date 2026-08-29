import Foundation
import Security

enum KeychainStore {
    private static let service = "com.example.FitbitHealthSync.oauth"

    static func save(_ token: FitbitToken) throws {
        let data = try JSONEncoder().encode(token)
        let query = [kSecClass: kSecClassGenericPassword, kSecAttrService: service] as CFDictionary
        SecItemDelete(query)
        let item = [kSecClass: kSecClassGenericPassword, kSecAttrService: service, kSecValueData: data] as CFDictionary
        guard SecItemAdd(item, nil) == errSecSuccess else { throw URLError(.cannotCreateFile) }
    }

    static func load() -> FitbitToken? {
        let query = [kSecClass: kSecClassGenericPassword, kSecAttrService: service,
                     kSecReturnData: true, kSecMatchLimit: kSecMatchLimitOne] as CFDictionary
        var result: CFTypeRef?
        guard SecItemCopyMatching(query, &result) == errSecSuccess, let data = result as? Data else { return nil }
        return try? JSONDecoder().decode(FitbitToken.self, from: data)
    }

    static func clear() {
        SecItemDelete([kSecClass: kSecClassGenericPassword, kSecAttrService: service] as CFDictionary)
    }
}

