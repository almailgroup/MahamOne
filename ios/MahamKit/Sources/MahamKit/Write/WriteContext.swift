import Foundation

/// One user action's view of the company while it changes records, as a
/// Dexie transaction is on the web: it reads the company's records as they
/// stand, with the action's own changes laid over them (an action reads
/// what it just wrote), and gathers the changes for the sync engine to
/// apply and send as one group (`SyncEngine.perform(group:)`).
///
/// The web's write functions (src/db/*.ts) are ported as functions that
/// take a `WriteContext`: what they `get`/`all` here is what the web's
/// `db.<table>.get`/`where('companyId')…toArray()` would read, and what
/// they `put`/`delete` is what the web would write. Ids and the clock come
/// from here, so the parity tests can fix them.
public final class WriteContext {
  public let companyId: String
  /// The signed-in account (`activityAuthor`'s id); nil for a company kept on this device only.
  public let userId: String?
  /// The name the team knows them by, for the activity log.
  public let userName: String?
  public let role: MemberRole
  /// The moment of the action (`new Date()`).
  public let now: Date
  /// Today on this device ("2026-11-28"), as the web's `today()`.
  public let today: String

  private let base: (String) -> [String: JSONValue]
  private var loaded: [String: [String: JSONValue]] = [:]
  private var overlay: [String: [String: JSONValue?]] = [:]
  private var order: [RecordChange] = []
  private let makeId: () -> String

  public init(
    companyId: String, userId: String?, userName: String? = nil, role: MemberRole, now: Date = Date(),
    today: String? = nil, makeId: @escaping () -> String = { MahamKit.newId() },
    records: @escaping (String) -> [String: JSONValue]
  ) {
    self.companyId = companyId
    self.userId = userId
    self.userName = userName
    self.role = role
    self.now = now
    self.today = today ?? ISODates.today(now: now)
    self.makeId = makeId
    self.base = records
  }

  // MARK: Reading

  private func table(_ name: String) -> [String: JSONValue] {
    if let found = loaded[name] { return found }
    let records = base(name)
    loaded[name] = records
    return records
  }

  /// A record by id, with this action's changes (`db.<table>.get(id)`).
  public func get(_ table: String, _ id: String) -> JSONValue? {
    if let changed = overlay[table], let entry = changed[id] { return entry }
    return self.table(table)[id]
  }

  /// A kind's records, with this action's changes, in id order (how Dexie
  /// returns a table or a `companyId` index: by primary key).
  public func all(_ table: String) -> [JSONValue] {
    var merged = self.table(table)
    for (id, entry) in overlay[table] ?? [:] {
      merged[id] = entry
    }
    return merged.keys.sorted().compactMap { merged[$0] }
  }

  /// A kind's records that match `filter`.
  public func all(_ table: String, where filter: (JSONValue) -> Bool) -> [JSONValue] {
    all(table).filter(filter)
  }

  // MARK: Writing

  /// Stores a record whole (`db.<table>.put(record)`); its `id` names it.
  public func put(_ table: String, _ record: JSONValue) {
    guard let id = record["id"]?.string else { return }
    overlay[table, default: [:]][id] = .some(record)
    order.append(.put(table: table, record: record))
  }

  /// Removes a record (`db.<table>.delete(id)`).
  public func delete(_ table: String, _ id: String) {
    overlay[table, default: [:]][id] = .some(nil)
    order.append(.delete(table: table, id: id))
  }

  /// A new id (`newId()`).
  public func newId() -> String { makeId() }

  /// A short id for line items and nested rows (`shortId()`: the first 12
  /// hex digits of a new id).
  public func shortId() -> String {
    String(newId().replacingOccurrences(of: "-", with: "").prefix(12))
  }

  /// The moment as `new Date().toISOString()` writes it.
  public var stamp: String { Defaults.nowStamp(now) }

  /// The action's changes, once per record: the last write of each wins,
  /// in the order each record was first written.
  public var changes: [RecordChange] {
    var seen: [String: Int] = [:]
    var result: [RecordChange] = []
    for change in order {
      let key: String
      switch change {
      case .put(let table, let record): key = "\(table)/\(record["id"]?.string ?? "")"
      case .delete(let table, let id): key = "\(table)/\(id)"
      }
      if let index = seen[key] {
        result[index] = change
      } else {
        seen[key] = result.count
        result.append(change)
      }
    }
    return result
  }

  /// The tables this action changed.
  public var changedTables: Set<String> { Set(order.map(\.table)) }
}

// MARK: The activity log

/// What happened, in words (`ActivityMessage`): an English key the reader's
/// language can show later, its variables, amounts (written in the
/// reader's way later) and Arabic names.
public struct ActivityMessage: Sendable {
  public var text: String
  public var vars: [String: String]
  public var money: [String: (amount: Double, currency: String)]
  public var arabic: [String: String?]

  public init(
    _ text: String, vars: [String: String] = [:], money: [String: (amount: Double, currency: String)] = [:],
    arabic: [String: String?] = [:]
  ) {
    self.text = text
    self.vars = vars
    self.money = money
    self.arabic = arabic
  }
}

/// What an activity is about besides its subject (`refs` of `logActivity`).
public struct ActivityRefs: Sendable {
  public var clientId: String?
  public var documentId: String?
  public var employeeId: String?
  public var confidential: Bool

  public init(clientId: String? = nil, documentId: String? = nil, employeeId: String? = nil, confidential: Bool = false) {
    self.clientId = clientId
    self.documentId = documentId
    self.employeeId = employeeId
    self.confidential = confidential
  }
}

extension WriteContext {
  /// `logActivity`: one line of the company's change log, named after the
  /// signed-in person in a company kept in the cloud.
  public func logActivity(
    entity: String, entityId: String, action: String, message: ActivityMessage, refs: ActivityRefs = ActivityRefs()
  ) {
    var fields: [(String, JSONValue)] = [
      ("id", .string(newId())),
      ("companyId", .string(companyId)),
      ("at", .string(stamp)),
    ]
    if let userId, !userId.isEmpty {
      fields.append(("by", .string(userId)))
      let name = String((userName ?? "").trimmingCharacters(in: .whitespacesAndNewlines).prefix(200))
      if !name.isEmpty { fields.append(("byName", .string(name))) }
    }
    fields.append(("entity", .string(entity)))
    fields.append(("entityId", .string(entityId)))
    fields.append(("clientId", refs.clientId.map(JSONValue.string) ?? .null))
    fields.append(("documentId", refs.documentId.map(JSONValue.string) ?? .null))
    if let employee = refs.employeeId, !employee.isEmpty { fields.append(("employeeId", .string(employee))) }
    if refs.confidential { fields.append(("confidential", .bool(true))) }
    fields.append(("action", .string(action)))
    fields.append(("message", .string(I18n.interpolate(message.text, message.vars))))
    fields.append(("messageKey", .string(message.text)))
    fields.append(("messageVars", .object(message.vars.mapValues(JSONValue.string))))
    if !message.money.isEmpty {
      fields.append(
        (
          "messageMoney",
          .object(
            message.money.mapValues {
              .object(["amount": .number($0.amount), "currency": .string($0.currency)])
            })
        ))
    }
    var arabic: [String: JSONValue] = [:]
    for (key, value) in message.arabic {
      let trimmed = (value ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
      if !trimmed.isEmpty { arabic[key] = .string(trimmed) }
    }
    if !arabic.isEmpty { fields.append(("messageVarsAr", .object(arabic))) }
    put("activities", .object(Dictionary(fields, uniquingKeysWith: { _, last in last })))
  }

  /// `logActivity` with a plain message, kept as written.
  public func logActivity(entity: String, entityId: String, action: String, plain: String, refs: ActivityRefs = ActivityRefs()) {
    var fields: [String: JSONValue] = [
      "id": .string(newId()), "companyId": .string(companyId), "at": .string(stamp),
      "entity": .string(entity), "entityId": .string(entityId),
      "clientId": refs.clientId.map(JSONValue.string) ?? .null,
      "documentId": refs.documentId.map(JSONValue.string) ?? .null,
      "action": .string(action), "message": .string(plain),
    ]
    if let userId, !userId.isEmpty {
      fields["by"] = .string(userId)
      let name = String((userName ?? "").trimmingCharacters(in: .whitespacesAndNewlines).prefix(200))
      if !name.isEmpty { fields["byName"] = .string(name) }
    }
    if let employee = refs.employeeId, !employee.isEmpty { fields["employeeId"] = .string(employee) }
    if refs.confidential { fields["confidential"] = .bool(true) }
    put("activities", .object(fields))
  }
}

/// An action the web's rules refuse, with the web's English message (the
/// app shows it through `t`, so the reader gets it in their language), as
/// the web's write functions throw `Error(message)`.
public struct WriteFailure: Error, Equatable, Sendable, CustomStringConvertible {
  public let message: String
  /// Variables of the message (`{number}`, …), filled in when it is shown.
  public let vars: [String: String]

  public init(_ message: String, _ vars: [String: String] = [:]) {
    self.message = message
    self.vars = vars
  }

  /// The message in English, as the web's `Error.message` reads.
  public var description: String { I18n.interpolate(message, vars) }
}
