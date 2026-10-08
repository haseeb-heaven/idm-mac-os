import Foundation
import Security
public enum CredentialStore {
    public static func save(username: String, password: String, jobID: UUID) throws {
        let query: [String: Any] = [kSecClass as String:kSecClassGenericPassword,
            kSecAttrService as String:"local.haseebheaven.idmmac", kSecAttrAccount as String:jobID.uuidString]
        let data = Data((username + ":" + password).utf8)
        let existing = SecItemUpdate(query as CFDictionary, [kSecValueData as String:data] as CFDictionary)
        if existing == errSecItemNotFound {
            var item = query; item[kSecValueData as String] = data
            let status = SecItemAdd(item as CFDictionary, nil)
            guard status == errSecSuccess else { throw DownloadError.storage("Keychain status \(status)") }
        } else if existing != errSecSuccess { throw DownloadError.storage("Keychain status \(existing)") }
    }
    public static func authorization(jobID: UUID) throws -> String? {
        let query: [String: Any] = [kSecClass as String:kSecClassGenericPassword,
            kSecAttrService as String:"local.haseebheaven.idmmac", kSecAttrAccount as String:jobID.uuidString,
            kSecReturnData as String:true, kSecMatchLimit as String:kSecMatchLimitOne]
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = result as? Data else { throw DownloadError.storage("Keychain status \(status)") }
        return "Basic " + data.base64EncodedString()
    }
    public static func delete(jobID: UUID) throws {
        let status = SecItemDelete([kSecClass as String:kSecClassGenericPassword,
            kSecAttrService as String:"local.haseebheaven.idmmac", kSecAttrAccount as String:jobID.uuidString] as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw DownloadError.storage("Keychain status \(status)") }
    }
}
