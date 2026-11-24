import Foundation

/// Where the app finds Maham One: its Supabase project and its websites.
///
/// The key is the project's **publishable** key, public by design (every
/// request runs as the signed-in person, under the database's rules). A
/// secret key would open every company's books, so it is refused here, as
/// the web apps refuse it.
public struct MahamConfig: Sendable, Equatable {
  public let supabaseURL: URL
  public let publishableKey: String
  /// Maham One on the web, for what the app opens there.
  public let webURL: URL
  /// Maham Tasks on the web.
  public let tasksWebURL: URL

  public init(
    supabaseURL: URL,
    publishableKey: String,
    webURL: URL = URL(string: "https://mahamone.com")!,
    tasksWebURL: URL = URL(string: "https://tasks.mahamone.com")!
  ) throws {
    let key = publishableKey.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !key.isEmpty else { throw MahamError.configuration("The publishable key is missing.") }
    guard !Self.isSecret(key) else {
      throw MahamError.configuration(
        "That is a secret key. The app only takes the publishable key (sb_publishable_…).")
    }
    self.supabaseURL = supabaseURL
    self.publishableKey = key
    self.webURL = webURL
    self.tasksWebURL = tasksWebURL
  }

  /// A secret key, or an old-style service-role JWT.
  static func isSecret(_ key: String) -> Bool {
    if key.hasPrefix("sb_secret_") { return true }
    guard let payload = JWT.payload(key) else { return false }
    return (payload["role"] as? String) == "service_role"
  }

  /// Reads the values the app's Info.plist carries (from Config/*.xcconfig).
  public static func fromInfoDictionary(_ info: [String: Any]) throws -> MahamConfig {
    guard
      let urlString = info["SupabaseURL"] as? String,
      let url = URL(string: urlString), url.scheme == "https"
    else { throw MahamError.configuration("SupabaseURL is missing from the app's settings.") }
    guard let key = info["SupabasePublishableKey"] as? String else {
      throw MahamError.configuration("SupabasePublishableKey is missing from the app's settings.")
    }
    return try MahamConfig(supabaseURL: url, publishableKey: key)
  }
}

/// Reading a JWT's payload, without checking it: only for what the client
/// may know about its own token (its expiry, its assurance level).
enum JWT {
  static func payload(_ token: String) -> [String: Any]? {
    let parts = token.split(separator: ".")
    guard parts.count == 3 else { return nil }
    var base64 = String(parts[1])
      .replacingOccurrences(of: "-", with: "+")
      .replacingOccurrences(of: "_", with: "/")
    while base64.count % 4 != 0 { base64 += "=" }
    guard
      let data = Data(base64Encoded: base64),
      let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    else { return nil }
    return object
  }
}
