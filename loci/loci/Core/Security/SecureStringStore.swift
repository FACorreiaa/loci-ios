import Foundation
import Security

public enum SecureStoreError: LocalizedError, Equatable {
    case readFailed(OSStatus)
    case writeFailed(OSStatus)
    case deleteFailed(OSStatus)
    case invalidEncoding

    public var errorDescription: String? {
        switch self {
        case .readFailed(let status):
            return "Failed to read from Keychain (OSStatus: \(status))."
        case .writeFailed(let status):
            return "Failed to write to Keychain (OSStatus: \(status))."
        case .deleteFailed(let status):
            return "Failed to delete from Keychain (OSStatus: \(status))."
        case .invalidEncoding:
            return "Data in Keychain could not be encoded as a UTF-8 string."
        }
    }
}

public protocol SecureStringStoring: Sendable {
    func string(for key: String) throws -> String?
    func setString(_ value: String, for key: String) throws
    func removeValue(for key: String) throws
}

public final class KeychainStringStore: SecureStringStoring, @unchecked Sendable {
    private let service: String

    public init(service: String = Bundle.main.bundleIdentifier ?? "com.fernandocorreia.loci") {
        self.service = service
    }

    public func string(for key: String) throws -> String? {
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: key,
            kSecAttrSynchronizable: kCFBooleanFalse as Any,
            kSecReturnData: true,
            kSecMatchLimit: kSecMatchLimitOne
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status != errSecItemNotFound else { return nil }
        guard status == errSecSuccess else { throw SecureStoreError.readFailed(status) }
        guard let data = result as? Data, let value = String(data: data, encoding: .utf8) else {
            throw SecureStoreError.invalidEncoding
        }
        return value
    }

    public func setString(_ value: String, for key: String) throws {
        let data = Data(value.utf8)
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: key,
            kSecAttrSynchronizable: kCFBooleanFalse as Any
        ]

        let attributes: [CFString: Any] = [
            kSecValueData: data,
            kSecAttrAccessible: kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        ]

        let updateStatus = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if updateStatus == errSecSuccess { return }
        guard updateStatus == errSecItemNotFound else { throw SecureStoreError.writeFailed(updateStatus) }

        var insert = query
        attributes.forEach { insert[$0.key] = $0.value }
        let addStatus = SecItemAdd(insert as CFDictionary, nil)
        guard addStatus == errSecSuccess else { throw SecureStoreError.writeFailed(addStatus) }
    }

    public func removeValue(for key: String) throws {
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: key,
            kSecAttrSynchronizable: kCFBooleanFalse as Any
        ]
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw SecureStoreError.deleteFailed(status)
        }
    }
}
