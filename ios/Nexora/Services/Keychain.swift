import Foundation
import Security

/// Les clés d'API et le jeton GitHub, rangés dans le trousseau d'iOS (jamais dans
/// les réglages ni dans les sauvegardes en clair).
enum Keychain {
    private static let service = "com.maxlestage.nexora.keys"

    /// Les valeurs déjà lues (ou absentes), gardées en mémoire. Lire le trousseau
    /// est un appel au système (`SecItemCopyMatching`), et la clé d'un fournisseur
    /// est demandée par beaucoup d'écrans (`hasKey`, `isReady`, `readyProviders`…),
    /// plusieurs fois par affichage, y compris pendant une réponse. L'app est seule à
    /// écrire sous ce service : une écriture oublie la valeur gardée (relue au
    /// prochain usage), `deleteAll` oublie tout. Une lecture qui échoue pour une
    /// autre raison qu'une absence (appareil pas encore déverrouillé…) n'est pas
    /// retenue : elle sera retentée.
    private static let memory = Memory()

    private final class Memory: @unchecked Sendable {
        private let lock = NSLock()
        /// `.some(nil)` : absente du trousseau.
        private var values: [String: String?] = [:]

        func get(_ account: String) -> String?? { lock.withLock { values[account] } }
        func remember(_ account: String, _ value: String?) { lock.withLock { _ = values.updateValue(value, forKey: account) } }
        func forget(_ account: String) { lock.withLock { _ = values.removeValue(forKey: account) } }
        func forgetAll() { lock.withLock { values.removeAll() } }
    }

    static func get(_ account: String) -> String? {
        if let known = memory.get(account) { return known }
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var out: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &out)
        if status == errSecItemNotFound {
            memory.remember(account, nil)
            return nil
        }
        guard status == errSecSuccess, let data = out as? Data else { return nil }
        let value = String(data: data, encoding: .utf8)
        memory.remember(account, value)
        return value
    }

    static func set(_ value: String?, for account: String) {
        defer { memory.forget(account) }
        let base: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(base as CFDictionary)
        guard let value, !value.isEmpty else { return }
        var add = base
        add[kSecValueData as String] = Data(value.utf8)
        add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        SecItemAdd(add as CFDictionary, nil)
    }

    static func deleteAll() {
        defer { memory.forgetAll() }
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
        ]
        SecItemDelete(query as CFDictionary)
    }
}
