import Foundation
import MahamKit
import Security

/// The services the app and its widgets share, built once from the bundle's
/// settings (Config/*.xcconfig → Info.plist).
struct AppServices: Sendable {
  let config: MahamConfig
  let auth: AuthService
  let db: DatabaseClient
  let tasks: TasksRepository
  let one: OneRepository
  let cache: DiskCache
  let sessions: SessionStore

  /// Nil while the publishable key isn't set (the app says so).
  static let shared: AppServices? = make()

  private static func make() -> AppServices? {
    let info = Bundle.main.infoDictionary ?? [:]
    guard let config = try? MahamConfig.fromInfoDictionary(info) else { return nil }
    let transport = URLSessionTransport()
    let sessions = KeychainSessionStore(accessGroup: keychainGroup(info))
    let auth = AuthService(config: config, transport: transport, store: sessions)
    let db = DatabaseClient(auth: auth, transport: transport)
    return AppServices(
      config: config, auth: auth, db: db, tasks: TasksRepository(db: db),
      one: OneRepository(db: db), cache: DiskCache(directory: cacheDirectory(info)),
      sessions: sessions)
  }

  /// The group the app and the widgets share: "TEAMID.com.almailgroup…".
  /// The team prefix is read from the app's own Keychain entitlement at run
  /// time; without one (the simulator, unsigned), the default group is used.
  private static func keychainGroup(_ info: [String: Any]) -> String? {
    guard let group = info["KeychainGroup"] as? String, !group.isEmpty,
      let prefix = teamPrefix()
    else { return nil }
    return prefix + group
  }

  private static func teamPrefix() -> String? {
    // An item added without a group lands in the first one the app may use,
    // which starts with the team id.
    let probe: [String: Any] = [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: "com.almailgroup.mahamone.probe",
      kSecAttrAccount as String: "probe",
      kSecReturnAttributes as String: true,
    ]
    var result: CFTypeRef?
    var status = SecItemCopyMatching(probe as CFDictionary, &result)
    if status == errSecItemNotFound {
      var add = probe
      add[kSecValueData as String] = Data()
      status = SecItemAdd(add as CFDictionary, &result)
    }
    guard status == errSecSuccess,
      let attributes = result as? [String: Any],
      let group = attributes[kSecAttrAccessGroup as String] as? String,
      let dot = group.firstIndex(of: ".")
    else { return nil }
    return String(group[...dot])
  }

  /// The App Group's container, so the widgets see the same cache.
  private static func cacheDirectory(_ info: [String: Any]) -> URL {
    if let group = info["AppGroup"] as? String,
      let shared = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: group)
    {
      return shared.appendingPathComponent("Library/Caches/Maham", isDirectory: true)
    }
    return FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
      .appendingPathComponent("Maham", isDirectory: true)
  }
}
