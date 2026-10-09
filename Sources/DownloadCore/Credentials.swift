import Foundation
import Security
public enum CredentialStore {
    public static func save(username: String, password: String, jobID: UUID) throws {
        let query: [String: Any] = [kSecClass as String:kSecClassGenericPassword,
            kSecAttrService as String:"local.haseebheaven.macdownloadmanager", kSecAttrAccount as String:jobID.uuidString]
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
            kSecAttrService as String:"local.haseebheaven.macdownloadmanager", kSecAttrAccount as String:jobID.uuidString,
            kSecReturnData as String:true, kSecMatchLimit as String:kSecMatchLimitOne]
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = result as? Data else { throw DownloadError.storage("Keychain status \(status)") }
        return "Basic " + data.base64EncodedString()
    }
    public static func delete(jobID: UUID) throws {
        let status = SecItemDelete([kSecClass as String:kSecClassGenericPassword,
            kSecAttrService as String:"local.haseebheaven.macdownloadmanager", kSecAttrAccount as String:jobID.uuidString] as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw DownloadError.storage("Keychain status \(status)") }
    }
    public static func saveHeaders(_ headers:[String:String],jobID:UUID) throws {
        try BrowserHeaders.validate(headers)
        let query:[String:Any] = [kSecClass as String:kSecClassGenericPassword,kSecAttrService as String:"local.haseebheaven.macdownloadmanager.browser-headers",kSecAttrAccount as String:jobID.uuidString]
        let data=try JSONEncoder().encode(headers)
        let status=SecItemUpdate(query as CFDictionary,[kSecValueData as String:data] as CFDictionary)
        if status == errSecItemNotFound { var item=query;item[kSecValueData as String]=data;let added=SecItemAdd(item as CFDictionary,nil);guard added == errSecSuccess else { throw DownloadError.storage("Keychain status \(added)") } }
        else if status != errSecSuccess { throw DownloadError.storage("Keychain status \(status)") }
    }
    public static func headers(jobID:UUID) throws -> [String:String] {
        let query:[String:Any] = [kSecClass as String:kSecClassGenericPassword,kSecAttrService as String:"local.haseebheaven.macdownloadmanager.browser-headers",kSecAttrAccount as String:jobID.uuidString,kSecReturnData as String:true,kSecMatchLimit as String:kSecMatchLimitOne]
        var result:CFTypeRef?;let status=SecItemCopyMatching(query as CFDictionary,&result)
        if status == errSecItemNotFound { return [:] }
        guard status == errSecSuccess,let data=result as? Data else { throw DownloadError.storage("Keychain status \(status)") }
        let headers=try JSONDecoder().decode([String:String].self,from:data);try BrowserHeaders.validate(headers);return headers
    }
    public static func deleteHeaders(jobID:UUID) throws {
        let status=SecItemDelete([kSecClass as String:kSecClassGenericPassword,kSecAttrService as String:"local.haseebheaven.macdownloadmanager.browser-headers",kSecAttrAccount as String:jobID.uuidString] as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw DownloadError.storage("Keychain status \(status)") }
    }
}
