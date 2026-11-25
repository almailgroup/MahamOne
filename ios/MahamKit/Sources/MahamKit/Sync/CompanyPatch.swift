import Foundation

/// One field of the company record that changed on this device: set to
/// `value`, or removed (`value` nil). `base` is what it was in the copy this
/// device last had from the cloud; nil when it had none (JSON null is
/// `.null`, a different thing).
public struct CompanyOp: Sendable, Equatable {
  public var path: [String]
  public var value: JSONValue?
  public var base: JSONValue?

  public init(path: [String], value: JSONValue?, base: JSONValue? = nil) {
    self.path = path
    self.value = value
    self.base = base
  }

  public var remove: Bool { value == nil }

  /// As the web sends it to patch_company: `{path, value}` or `{path, remove: true}`, with `base` when known.
  public var json: JSONValue {
    var fields: [String: JSONValue] = ["path": .array(path.map { .string($0) })]
    if let value { fields["value"] = value } else { fields["remove"] = .bool(true) }
    if let base { fields["base"] = base }
    return .object(fields)
  }
}

/// The company record is changed on every device: its settings by owners and
/// admins, its document counters by anyone who numbers a document. So a
/// change travels as the fields that changed since the copy this device last
/// had from the cloud (its base), laid over the cloud's current copy. Ported
/// from src/cloud/company-patch.ts and src/cloud/numbering.ts; the database
/// does the same (patch_company, merge_numbering).
public enum CompanyPatch {
  private static let counter: Set<String> = ["next", "period"]

  /// Settings that are one value though they are objects: the company type
  /// travels whole, so two devices' types never mix.
  private static let whole: Set<String> = ["companyType"]

  /// Fields whose changes on two devices are never a conflict: counters merge, the time is the time.
  private static func quiet(_ path: [String]) -> Bool {
    path.first == "numbering" || path.first == "updatedAt"
  }

  private static func op(_ path: [String], _ value: JSONValue?, _ base: JSONValue?) -> CompanyOp {
    CompanyOp(path: path, value: value, base: base)
  }

  /// What changed from `base` to `local`: the leaves of nested objects;
  /// arrays and the settings that are one value as a whole; a numbering
  /// counter always with its period. Keys are visited in sorted order (the
  /// web visits them in insertion order; the ops never overlap, so the
  /// order changes nothing).
  public static func companyOps(base: JSONValue, local: JSONValue) -> [CompanyOp] {
    var ops: [CompanyOp] = []
    func walk(_ before: JSONValue?, _ after: JSONValue?, _ path: [String]) {
      if SyncJSON.sameData(before, after) { return }
      let isWhole = path.count == 1 && whole.contains(path[0])
      if case .some(.object(let old)) = before, case .some(.object(let new)) = after, !isWhole {
        let rule = path.count == 2 && path[0] == "numbering"
        if rule && (!SyncJSON.sameData(old["next"], new["next"]) || !SyncJSON.sameData(old["period"], new["period"])) {
          // A counter means nothing without its period: they go together.
          ops.append(op(path + ["next"], new["next"], old["next"]))
          ops.append(op(path + ["period"], new["period"], old["period"]))
        }
        for key in Set(old.keys).union(new.keys).sorted() {
          if rule && counter.contains(key) { continue }
          walk(old[key], new[key], path + [key])
        }
        return
      }
      if path.isEmpty { return }
      ops.append(op(path, after, before))
    }
    walk(base, local, [])
    return ops
  }

  /// Only document counters changed (what numbering a document does).
  public static func onlyCounters(_ ops: [CompanyOp]) -> Bool {
    !ops.isEmpty
      && ops.allSatisfy { $0.path.count == 3 && $0.path[0] == "numbering" && counter.contains($0.path[2]) }
  }

  static func getPath(_ target: JSONValue?, _ path: [String]) -> JSONValue? {
    var at = target
    for key in path {
      guard case .some(.object(let fields)) = at else { return nil }
      at = fields[key]
    }
    return at
  }

  static func setPath(_ target: [String: JSONValue], _ path: [String], _ value: JSONValue) -> [String: JSONValue] {
    guard let head = path.first else { return target }
    var copy = target
    if path.count == 1 {
      copy[head] = value
      return copy
    }
    let child: [String: JSONValue]
    if case .some(.object(let fields)) = target[head] { child = fields } else { child = [:] }
    copy[head] = .object(setPath(child, Array(path.dropFirst()), value))
    return copy
  }

  static func removePath(_ target: [String: JSONValue], _ path: [String]) -> [String: JSONValue] {
    guard let head = path.first, let child = target[head] else { return target }
    var copy = target
    if path.count == 1 {
      copy[head] = nil
      return copy
    }
    guard case .object(let fields) = child else { return target }
    copy[head] = .object(removePath(fields, Array(path.dropFirst())))
    return copy
  }

  /// Lays this device's changes over `current` (the cloud's copy): counters
  /// merge, every other field takes this device's value. `conflicts` lists
  /// the fields that had also changed in `current` since this device's base.
  public static func rebaseCompany(current: JSONValue, ops: [CompanyOp]) -> (data: JSONValue, conflicts: [[String]]) {
    guard case .object(let currentFields) = current else { return (current, []) }
    var data = currentFields
    var conflicts: [[String]] = []
    for change in ops {
      let now = getPath(current, change.path)
      let mine = change.value
      if !quiet(change.path) && !SyncJSON.sameData(now, change.base) && !SyncJSON.sameData(now, mine) {
        conflicts.append(change.path)
      }
      data = change.remove ? removePath(data, change.path) : setPath(data, change.path, change.value ?? .null)
    }
    if let numbering = mergeNumbering(current["numbering"], data["numbering"]) {
      data["numbering"] = numbering
    }
    return (.object(data), conflicts)
  }

  // MARK: Numbering (src/cloud/numbering.ts)

  /// For each kind of document the counter of the later period wins, and in
  /// the same period the higher counter. Pattern, padding and reset come
  /// from `next` (a change of reset takes `next` as it is).
  public static func mergeNumberingRule(_ old: JSONValue?, _ next: JSONValue?) -> JSONValue? {
    guard case .some(.object(var new)) = next else { return old }
    guard case .some(.object(let previous)) = old else { return next }
    // (old.reset ?? '') !== (next.reset ?? '')
    if !SyncJSON.strictEqual(orEmpty(previous["reset"]), orEmpty(new["reset"])) { return next }
    let oldPeriod = periodText(previous["period"])
    let newPeriod = periodText(new["period"])
    if SyncJSON.jsLess(oldPeriod, newPeriod) { return next }
    if SyncJSON.jsLess(newPeriod, oldPeriod) {
      new["period"] = .string(oldPeriod)
      new["next"] = previous["next"]
      return .object(new)
    }
    let oldNext = previous["next"]?.double ?? 0
    let newNext = new["next"]?.double ?? 0
    if oldNext > newNext {
      new["next"] = previous["next"]
      return .object(new)
    }
    return next
  }

  public static func mergeNumbering(_ old: JSONValue?, _ next: JSONValue?) -> JSONValue? {
    guard case .some(.object(let new)) = next else { return old }
    guard case .some(.object(let previous)) = old else { return next }
    var merged: [String: JSONValue] = [:]
    for key in Set(previous.keys).union(new.keys) {
      if let rule = mergeNumberingRule(previous[key], new[key]) { merged[key] = rule }
    }
    return .object(merged)
  }

  /// `value ?? ''`.
  private static func orEmpty(_ value: JSONValue?) -> JSONValue {
    switch value {
    case .none, .some(.null): return .string("")
    case .some(let other): return other
    }
  }

  /// `rule.period ?? ''` as a string (periods are strings: "2026", "2026-10" or "").
  private static func periodText(_ value: JSONValue?) -> String {
    switch value {
    case .none, .some(.null): return ""
    case .some(.string(let text)): return text
    case .some(let other): return SyncJSON.string(other)
    }
  }
}
