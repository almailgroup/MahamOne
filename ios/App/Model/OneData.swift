import Foundation
import MahamKit
import Observation

/// Every record of the company on screen, on this iPhone, as the web keeps
/// them in the browser (`src/cloud/sync.ts`): the sync engine downloads the
/// company once into a mirror on disk, then brings in what changes, every
/// minute and when the app comes back. Pages read records from here, by
/// kind, as raw JSON (typed views in `One/Records`); they redraw when
/// `revision` moves. Nothing is written to the cloud from here yet: the
/// engine's writable kinds are empty until each kind's rules match the web.
@MainActor
@Observable
final class OneData {
  enum Phase: Equatable {
    /// No company opened yet.
    case idle
    /// The company is being copied to this iPhone (records so far, of about `total`).
    case downloading(done: Int, total: Int)
    /// Its records are here.
    case ready
    /// The first download failed; what is here (if anything) stays.
    case failed(String)
  }

  private(set) var phase: Phase = .idle
  /// Moves each time the mirror changes, so pages read it again.
  private(set) var revision = 0
  /// The engine is talking to the cloud.
  private(set) var syncing = false
  private(set) var companyId: String?

  private let services: AppServices?
  /// Who saves, for the activity log (`user.fullName || user.email`).
  private var author: (id: String, name: String)?
  private var mirror: Mirror?
  private var engine: SyncEngine?
  private var watchers: [Task<Void, Never>] = []
  private var opening: Task<Void, Never>?
  /// What pages read, per table, until the mirror changes.
  @ObservationIgnored private var cache: [String: [JSONValue]] = [:]
  @ObservationIgnored private var byId: [String: [String: JSONValue]] = [:]

  init(services: AppServices?) {
    self.services = services
  }

  // MARK: Reading

  /// The records of a kind (none until the company is here).
  func records(_ kind: RecordKind) -> [JSONValue] {
    _ = revision
    if let found = cache[kind.rawValue] { return found }
    let list = mirror?.records(kind.rawValue) ?? []
    cache[kind.rawValue] = list
    return list
  }

  /// One record of a kind, by id.
  func record(_ kind: RecordKind, _ id: String) -> JSONValue? {
    _ = revision
    if let table = byId[kind.rawValue] { return table[id] }
    let table = mirror?.recordsById(kind.rawValue) ?? [:]
    byId[kind.rawValue] = table
    return table[id]
  }

  /// The company record (settings, numbering, branding), as on the web's `db.companies`.
  var company: JSONValue? {
    guard let companyId else { return nil }
    return record(.companies, companyId)
  }

  /// What the company's server has, as last asked (`link.features`): the
  /// suite's ports wait for it as the web does (`linkHasFeature`). Every
  /// company opened here is kept in the cloud.
  var cloud: SwCloud? {
    _ = revision
    guard let mirror else { return nil }
    return SwCloud(features: mirror.state.features ?? [])
  }

  /// The company is on this iPhone (at least partly, while it downloads again).
  var hasData: Bool {
    _ = revision
    return mirror != nil && phase != .idle
  }

  // MARK: Opening a company

  /// Opens the company's copy on this iPhone, or downloads it, and keeps it
  /// in step with the cloud. Opening the one already open just syncs it.
  func open(_ company: Company, userId: String, authorName: String = "") {
    author = (userId, authorName)
    if companyId == company.id {
      Task { await sync() }
      return
    }
    close()
    companyId = company.id
    opening = Task { await start(company, userId: userId) }
  }

  private func start(_ company: Company, userId: String) async {
    guard let services else { return }
    let directory = Self.directory(userId: userId, companyId: company.id)
    let api = SupabaseCloudAPI(db: services.db)
    let cloud = CloudCompany(id: company.id, name: company.name, role: company.role, members: company.members)
    let opened: Mirror
    do {
      if let existing = try? Mirror.open(directory: directory), existing.state.status != .removed,
        existing.state.userId == userId
      {
        opened = existing
      } else {
        phase = .downloading(done: 0, total: 0)
        opened = try await SyncEngine.startDownload(cloud, userId: userId, api: api, directory: directory)
      }
    } catch {
      guard companyId == company.id else { return }
      phase = .failed(Self.describe(error))
      return
    }
    guard companyId == company.id else { return }
    var configuration = SyncConfiguration()
    // Only the kinds whose saving rules are ported and tested against the web's.
    configuration.writableKinds = OneWritable.kinds
    configuration.onProgress = { [weak self] progress in
      Task { @MainActor in
        guard let self, self.companyId == company.id, progress.kind == .download else { return }
        self.phase = .downloading(done: progress.done, total: progress.total)
      }
    }
    let engine = SyncEngine(mirror: opened, api: api, userId: userId, configuration: configuration)
    mirror = opened
    self.engine = engine
    invalidate()
    phase = opened.state.status == .downloading ? .downloading(done: 0, total: opened.state.total ?? 0) : .ready
    watch(opened, engine: engine, companyId: company.id)
    await engine.start()
  }

  /// Redraws on every change of the mirror, and follows the engine's status.
  private func watch(_ mirror: Mirror, engine: SyncEngine, companyId: String) {
    let changes = mirror.changes()
    watchers.append(
      Task { [weak self] in
        for await change in changes {
          guard let self, self.companyId == companyId else { return }
          // The sync's own bookkeeping (cursor, last sync) changes no record.
          if change.tables.isEmpty { continue }
          self.invalidate()
        }
      })
    watchers.append(
      Task { [weak self] in
        let updates = await engine.statusUpdates()
        for await status in updates {
          guard let self, self.companyId == companyId else { return }
          self.syncing = status.phase == .syncing
          if status.syncedOnce, mirror.state.status == .ready {
            self.phase = .ready
          } else if status.phase == .error, case .downloading = self.phase, mirror.state.status == .downloading {
            self.phase = .failed(Self.describe(status.error))
          }
        }
      })
  }

  private func invalidate() {
    cache = [:]
    byId = [:]
    revision &+= 1
  }

  // MARK: Saving

  /// Saves one user action, as the web saves one in a Dexie transaction:
  /// `body` reads the company's records and writes its changes through the
  /// context (the ports of the web's write functions, in MahamKit/Write);
  /// the sync engine then applies them here and queues them for the cloud,
  /// all or nothing. Throws `SyncWriteError` with the web's words when the
  /// rules refuse it.
  @discardableResult
  func write<T>(_ body: (WriteContext) throws -> T) async throws -> T {
    guard let mirror, let engine, let companyId else {
      throw SyncWriteError.refused("This company is still being downloaded. Try again in a moment.")
    }
    let context = WriteContext(
      companyId: companyId, userId: author?.id, userName: author?.name, role: mirror.state.role,
      records: { mirror.recordsById($0) })
    let result = try body(context)
    let changes = context.changes
    if !changes.isEmpty {
      try await engine.perform(group: changes)
      invalidate()
    }
    return result
  }

  /// A kind of record this app may save yet.
  static func canWrite(_ kind: RecordKind) -> Bool {
    OneWritable.kinds.contains(kind.rawValue)
  }

  /// The signed-in person's link to the company, as the web's write
  /// functions read it from `db.syncState` (who they are, their role, and
  /// whether the owner lets them approve). Nil until the company is open.
  var writeLink: DcLink? {
    guard let mirror else { return nil }
    let state = mirror.state
    return DcLink(userId: state.userId, role: state.role, approver: state.approver == true)
  }

  /// The next counter of a kind from the company's counter in the cloud
  /// (`reserve_number`), for a write that gives a new number: the web takes
  /// it before saving, so two devices never give the same number. Nil
  /// offline, with no answer in 3 s, or with nothing to ask: the write then
  /// numbers it on this iPhone, as the web does.
  func reserveNumber(_ request: DcCounterRequest?) async -> ReservedCounter? {
    guard let request, let engine else { return nil }
    return await engine.reserveNumber(kind: request.kind, date: request.date, min: request.min)
  }

  // MARK: Syncing

  /// Brings in what changed now (pull to refresh, Sync now).
  func sync() async {
    guard let engine else { return }
    syncing = true
    defer { syncing = false }
    _ = try? await engine.sync()
    if mirror?.state.status == .ready { phase = .ready }
  }

  /// The app came back into view.
  func appBecameActive() async {
    await engine?.appBecameActive()
  }

  /// Stops syncing and lets go of the company (another one opens, or signing out).
  func close() {
    opening?.cancel()
    opening = nil
    watchers.forEach { $0.cancel() }
    watchers = []
    if let engine { Task { await engine.stop() } }
    engine = nil
    mirror = nil
    companyId = nil
    phase = .idle
    syncing = false
    invalidate()
  }

  /// Signing out: the copies of this account's companies leave the iPhone.
  func removeAll(userId: String) {
    close()
    try? FileManager.default.removeItem(at: Self.root.appendingPathComponent(userId, isDirectory: true))
  }

  // MARK: Where the copies live

  private static var root: URL {
    let caches =
      FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
      ?? FileManager.default.temporaryDirectory
    #if DEBUG
      if PreviewMode.isOn { return caches.appendingPathComponent("MahamPreview/mirrors", isDirectory: true) }
    #endif
    return caches.appendingPathComponent("Maham/mirrors", isDirectory: true)
  }

  static func directory(userId: String, companyId: String) -> URL {
    root.appendingPathComponent(userId, isDirectory: true).appendingPathComponent(companyId, isDirectory: true)
  }

  private static func describe(_ error: Error) -> String {
    describe((error as? CloudError)?.code)
  }

  /// The web's words for a sync that failed.
  private static func describe(_ code: CloudErrorCode?) -> String {
    code == .offline
      ? t("No connection. Check your internet and try again.")
      : t("Something went wrong. Try again in a moment.")
  }

  #if DEBUG
    /// Preview mode (App/Preview): a mirror filled with the made-up records,
    /// never synced.
    func openPreview(_ company: Company, userId: String, records: [String: [JSONValue]]) {
      close()
      companyId = company.id
      let directory = Self.directory(userId: userId, companyId: company.id)
      var state = SyncState(
        companyId: company.id, userId: userId, role: company.role, status: .ready, name: company.name,
        linkedAt: Date())
      state.cursor = 1
      guard let made = try? Mirror.seeded(directory: directory, state: state, records: records) else { return }
      mirror = made
      author = (userId, "Sample User")
      // An engine that is never started: saving works on the made-up data, nothing is sent.
      if let services {
        var configuration = SyncConfiguration()
        configuration.writableKinds = OneWritable.kinds
        engine = SyncEngine(
          mirror: made, api: SupabaseCloudAPI(db: services.db), userId: userId, configuration: configuration)
      }
      phase = .ready
      invalidate()
    }
  #endif
}
