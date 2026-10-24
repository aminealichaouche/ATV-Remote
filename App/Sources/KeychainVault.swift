import Foundation
import Security

actor KeychainVault {
    private let service = "local.RoomRemote.device-secrets.v1"

    func data(forKey key: String) throws -> Data? {
        var query = baseQuery(key)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess else { throw failure(status) }
        guard let data = result as? Data else { throw RemoteFailure.message("Saved pairing data could not be read.") }
        return data
    }

    func store(_ data: Data, forKey key: String) throws {
        let query = baseQuery(key)
        let attributes: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        ]
        let updateStatus = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if updateStatus == errSecSuccess { return }
        guard updateStatus == errSecItemNotFound else { throw failure(updateStatus) }
        var insertion = query
        attributes.forEach { insertion[$0.key] = $0.value }
        let addStatus = SecItemAdd(insertion as CFDictionary, nil)
        guard addStatus == errSecSuccess else { throw failure(addStatus) }
    }

    /// An Auto winner may refresh its token only while both original records
    /// still exist unchanged. Read/check/update stays in this actor without
    /// suspension, and never creates a record removed by Forget/Re-pair.
    func refreshExistingToken(_ data: Data, forKey key: String, expectedToken: Data,
                              certificateKey: String, expectedCertificate: Data) throws -> Bool {
        guard try self.data(forKey: key) == expectedToken,
              try self.data(forKey: certificateKey) == expectedCertificate else { return false }
        let status = SecItemUpdate(baseQuery(key) as CFDictionary, [kSecValueData: data] as CFDictionary)
        if status == errSecItemNotFound { return false }
        guard status == errSecSuccess else { throw failure(status) }
        return true
    }

    func delete(forKey key: String) throws {
        let status = SecItemDelete(baseQuery(key) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw failure(status) }
    }

    private func baseQuery(_ key: String) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: service,
         kSecAttrAccount as String: key,
         kSecAttrSynchronizable as String: false]
    }
    private func failure(_ status: OSStatus) -> RemoteFailure {
        .message("Secure pairing storage is unavailable (\(status)). Unlock your iPhone and try again.")
    }
}
