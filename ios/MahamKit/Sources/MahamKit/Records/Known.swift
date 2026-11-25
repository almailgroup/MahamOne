import Foundation

/// Values read from stored records may come from a newer version of the app
/// (on another device, through the cloud or a backup) and be missing from
/// this version's lists. Looking them up through these gives a fallback
/// instead of nothing, so an older version shows something sensible rather
/// than failing (src/lib/known.ts). The value itself stays in the record as
/// it was: a typed view never writes the fallback back.
public enum Known {
  /// Whether `value` is text and one of the keys of `map`.
  public static func isKnown<Value>(_ map: [String: Value], _ value: JSONValue?) -> Bool {
    guard case .string(let key)? = value else { return false }
    return map[key] != nil
  }

  /// Whether `value` is one of the keys of `map`.
  public static func isKnown<Value>(_ map: [String: Value], _ value: String?) -> Bool {
    guard let value else { return false }
    return map[value] != nil
  }

  /// `map[value]`, or `fallback` for a value this version doesn't know.
  public static func lookup<Value>(_ map: [String: Value], _ value: JSONValue?, _ fallback: Value) -> Value {
    guard case .string(let key)? = value, let found = map[key] else { return fallback }
    return found
  }

  /// `map[value]`, or `fallback` for a value this version doesn't know.
  public static func lookup<Value>(_ map: [String: Value], _ value: String?, _ fallback: Value) -> Value {
    guard let value, let found = map[value] else { return fallback }
    return found
  }

  /// The case of `Kind` a stored value names, or `fallback` for one this
  /// version doesn't know (or that isn't text).
  public static func lookup<Kind: RawRepresentable>(_ value: JSONValue?, _ fallback: Kind) -> Kind
  where Kind.RawValue == String {
    guard case .string(let raw)? = value else { return fallback }
    return Kind(rawValue: raw) ?? fallback
  }

  /// The case of `Kind` named `value`, or `fallback` for one this version doesn't know.
  public static func lookup<Kind: RawRepresentable>(_ value: String?, _ fallback: Kind) -> Kind
  where Kind.RawValue == String {
    guard let value else { return fallback }
    return Kind(rawValue: value) ?? fallback
  }
}
