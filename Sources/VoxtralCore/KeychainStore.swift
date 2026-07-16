import Foundation
import Security

public enum KeychainStore {
    public static let defaultService = "voxtral-transcription"
    static let account = "mistral-api-key"

    static func baseQuery(service: String) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: service,
         kSecAttrAccount as String: account]
    }

    public static func apiKey(service: String = defaultService) -> String? {
        var query = baseQuery(service: service)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else { return nil }
        return String(decoding: data, as: UTF8.self)
    }

    public static func setAPIKey(_ key: String, service: String = defaultService) throws {
        deleteAPIKey(service: service)
        var query = baseQuery(service: service)
        query[kSecValueData as String] = Data(key.utf8)
        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw NSError(domain: NSOSStatusErrorDomain, code: Int(status))
        }
    }

    public static func deleteAPIKey(service: String = defaultService) {
        SecItemDelete(baseQuery(service: service) as CFDictionary)
    }
}
