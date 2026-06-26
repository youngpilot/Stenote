import CryptoKit
import Foundation
import Security
import os

private let logger = Logger(subsystem: "com.youngpilot.Stenote", category: "Encryption")

/// AES-GCM encryption for data at rest. The 256-bit key is generated once and
/// kept in the Keychain (device-only, not iCloud-synced), so the encrypted blobs
/// in app preferences are unreadable without it. Used for the transcription
/// history; the same primitive ports directly to the iOS app.
@MainActor
final class EncryptionService {
    static let shared = EncryptionService()

    private let service = "com.youngpilot.Stenote"
    private let account = "com.youngpilot.Stenote.historyKey"
    private var cachedKey: SymmetricKey?

    private init() {}

    /// Encrypt to a self-describing blob (nonce + ciphertext + tag). Returns nil
    /// only if the key is unavailable — callers should treat that as "don't write".
    func encrypt(_ data: Data) -> Data? {
        guard let key = key() else { return nil }
        do {
            return try AES.GCM.seal(data, using: key).combined
        } catch {
            logger.error("encrypt failed: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    /// Decrypt a blob produced by `encrypt`. Returns nil on a missing key or
    /// tampered/corrupt data.
    func decrypt(_ data: Data) -> Data? {
        guard let key = key() else { return nil }
        do {
            let box = try AES.GCM.SealedBox(combined: data)
            return try AES.GCM.open(box, using: key)
        } catch {
            logger.error("decrypt failed: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    // MARK: - Key (Keychain)

    private func key() -> SymmetricKey? {
        if let cachedKey { return cachedKey }
        let key = loadKey() ?? generateAndStoreKey()
        cachedKey = key
        return key
    }

    private func loadKey() -> SymmetricKey? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess, let data = item as? Data else { return nil }
        return SymmetricKey(data: data)
    }

    private func generateAndStoreKey() -> SymmetricKey? {
        let key = SymmetricKey(size: .bits256)
        let data = key.withUnsafeBytes { Data($0) }
        let attributes: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
        ]
        SecItemDelete(attributes as CFDictionary)  // avoid a duplicate if a stale item exists
        let status = SecItemAdd(attributes as CFDictionary, nil)
        if status != errSecSuccess {
            logger.error("Keychain store failed: \(status, privacy: .public)")
            return nil
        }
        return key
    }
}
