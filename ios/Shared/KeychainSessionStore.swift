import Foundation
import MahamKit
import Security

/// The session in the Keychain, in a group the widgets share, readable after
/// the first unlock (so a widget can refresh while the phone is locked) and
/// never backed up to another device.
final class KeychainSessionStore: SessionStore, @unchecked Sendable {
  private let service = "com.almailgroup.mahamone.session"
  private let account = "current"
  private let accessGroup: String?
  private let lock = NSLock()

  init(accessGroup: String?) {
    self.accessGroup = accessGroup
  }

  private func query() -> [String: Any] {
    var query: [String: Any] = [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: service,
      kSecAttrAccount as String: account,
    ]
    if let accessGroup { query[kSecAttrAccessGroup as String] = accessGroup }
    return query
  }

  func load() -> AuthSession? {
    lock.withLock {
      var query = query()
      query[kSecReturnData as String] = true
      query[kSecMatchLimit as String] = kSecMatchLimitOne
      var item: CFTypeRef?
      guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
        let data = item as? Data
      else { return nil }
      return try? MahamJSON.decoder().decode(AuthSession.self, from: data)
    }
  }

  func save(_ session: AuthSession) {
    lock.withLock {
      guard let data = try? MahamJSON.encoder().encode(session) else { return }
      let attributes: [String: Any] = [
        kSecValueData as String: data,
        kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
      ]
      let status = SecItemUpdate(query() as CFDictionary, attributes as CFDictionary)
      if status == errSecItemNotFound {
        var add = query()
        add.merge(attributes) { $1 }
        SecItemAdd(add as CFDictionary, nil)
      }
    }
  }

  func clear() {
    lock.withLock {
      _ = SecItemDelete(query() as CFDictionary)
    }
  }
}
