import Foundation
import Security

/// Minimal wrapper over the macOS Keychain for router passwords. Each password
/// is a generic-password item keyed by SSID (the account) under one service.
/// Passwords live here rather than in UserDefaults/JSON so that multiple
/// networks' credentials aren't sitting on disk in plaintext.
enum Keychain {
    private static let service = "com.rcolburn.wifimonitor.router"

    static func setPassword(_ password: String, ssid: String) {
        // Replace any existing item so repeated saves don't fail with duplicates.
        deletePassword(ssid: ssid)
        guard !password.isEmpty, let data = password.data(using: .utf8) else { return }
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: ssid,
            kSecValueData as String: data,
        ]
        SecItemAdd(query as CFDictionary, nil)
    }

    static func password(ssid: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: ssid,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data,
              let password = String(data: data, encoding: .utf8) else {
            return nil
        }
        return password
    }

    static func deletePassword(ssid: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: ssid,
        ]
        SecItemDelete(query as CFDictionary)
    }
}
