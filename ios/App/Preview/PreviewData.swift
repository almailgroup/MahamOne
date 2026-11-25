#if DEBUG
  // Preview mode's made-up account (see PreviewMode.swift). Every name here is
  // invented: no person, company or record is real, and nothing is read from
  // or sent to a database.

  import Foundation
  import MahamKit

  enum PreviewData {
    static let userId = "00000000-0000-4000-8000-00000000a001"
    static let managerId = "00000000-0000-4000-8000-00000000a002"
    static let email = "sample.user@example.com"

    /// The company on screen: the owner's, in Kuwaiti dinars (the shell's
    /// currency while no company profile is loaded).
    static let company = Company(
      id: "00000000-0000-4000-8000-00000000c001", name: "Sample Trading Co.", role: .owner, members: 4)

    /// Signed in, with a token that never needs refreshing (and is never sent).
    static let session = AuthSession(
      accessToken: "preview", refreshToken: "preview", expiresAt: .distantFuture,
      user: AuthUser(id: userId, email: email))

    /// The app's services as preview mode runs them: every request is
    /// answered "offline" (which the stores take quietly, keeping what they
    /// have), the session is kept in memory, never in the Keychain, and the
    /// cache, a folder of its own, holds the sample data.
    static func makeServices(language: Language) -> AppServices? {
      // `.invalid` never resolves; nothing is sent there anyway.
      guard let url = URL(string: "https://preview.invalid"),
        let config = try? MahamConfig(supabaseURL: url, publishableKey: "sb_publishable_preview")
      else { return nil }
      let transport = OfflineTransport()
      let sessions = MemorySessionStore(session)
      let auth = AuthService(config: config, transport: transport, store: sessions)
      let db = DatabaseClient(auth: auth, transport: transport)
      let cache = DiskCache(directory: cacheDirectory)
      seed(cache, language: language)
      return AppServices(
        config: config, auth: auth, db: db, tasks: TasksRepository(db: db), one: OneRepository(db: db),
        cache: cache, sessions: sessions)
    }

    /// Not the account's own cache: that is neither read nor overwritten.
    private static var cacheDirectory: URL {
      let caches =
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
        ?? FileManager.default.temporaryDirectory
      return caches.appendingPathComponent("MahamPreview", isDirectory: true)
    }

    /// What the stores read at launch, under their own keys: the companies
    /// (`BusinessStore`) and Maham Tasks' copy (`TasksStore`). Written afresh
    /// each launch, so the due dates are relative to today.
    private static func seed(_ cache: DiskCache, language: Language) {
      cache.clear()
      cache.save([company], as: "companies")
      cache.save(tasksCopy(language: language), as: "tasks")
    }

    // MARK: Maham Tasks

    private static let officeMoveId = "00000000-0000-4000-8000-00000000b001"
    private static let yearEndId = "00000000-0000-4000-8000-00000000b002"

    /// The sample person's work: one late, two due today, two coming up, one
    /// without a date and one finished today, in two projects.
    private static func tasksCopy(language: Language, now: Date = Date()) -> TasksCopy {
      let arabic = language == .ar
      func text(_ en: String, _ ar: String) -> String { arabic ? ar : en }
      let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = MahamDates.kuwait
        return calendar
      }()
      let today = calendar.startOfDay(for: now)
      func day(_ offset: Int, at hour: Int) -> Date? {
        calendar.date(byAdding: DateComponents(day: offset, hour: hour), to: today)
      }

      let team =
        decode(
          [TasksProfile].self,
          [
            [
              "id": userId, "email": email, "full_name": text("Sample User", "مستخدم تجريبي"), "role": "admin",
              "job_title": text("Owner", "المالك"),
            ],
            [
              "id": managerId, "email": "sample.manager@example.com",
              "full_name": text("Sample Manager", "مدير تجريبي"), "role": "manager",
            ],
          ]) ?? []
      let projects =
        decode(
          [TasksProject].self,
          [
            ["id": officeMoveId, "name": text("Office move", "نقل المكتب")],
            ["id": yearEndId, "name": text("Year-end close", "إقفال نهاية السنة")],
          ]) ?? []
      let notifications =
        decode(
          [TaskNotification].self,
          [
            [
              "id": "preview-notification-1", "type": "task_assigned",
              "title": text("Sample Manager assigned you a task", "أسند إليك مدير تجريبي مهمة"),
              "task_id": "preview-task-1", "actor_id": managerId,
              "created_at": MahamDates.timestamp(now.addingTimeInterval(-3600)),
            ]
          ]) ?? []

      let mine = [userId]
      let tasks = [
        TaskItem(
          id: "preview-task-1", projectId: officeMoveId,
          title: text("Renew the trade licence", "تجديد الرخصة التجارية"), status: .inProgress, priority: .high,
          dueAt: day(-1, at: 17), position: 1, createdBy: managerId, assigneeIds: mine),
        TaskItem(
          id: "preview-task-2", projectId: yearEndId,
          title: text("Approve this month's payroll", "اعتماد رواتب هذا الشهر"), priority: .urgent,
          dueAt: day(0, at: 23), position: 2, createdBy: userId, assigneeIds: mine),
        TaskItem(
          id: "preview-task-3", title: text("Call the landlord about the lease", "الاتصال بالمالك بشأن عقد الإيجار"),
          dueAt: day(0, at: 22), position: 3, createdBy: userId, assigneeIds: mine),
        TaskItem(
          id: "preview-task-4", projectId: yearEndId,
          title: text("Prepare the stock count sheets", "تجهيز أوراق جرد المخزون"), dueAt: day(2, at: 12),
          position: 4, createdBy: managerId, assigneeIds: mine),
        TaskItem(
          id: "preview-task-5", projectId: officeMoveId, title: text("Book the movers", "حجز شركة النقل"),
          priority: .low, dueAt: day(6, at: 10), position: 5, createdBy: userId, assigneeIds: mine),
        TaskItem(
          id: "preview-task-6", title: text("Tidy up the shared folder", "ترتيب المجلد المشترك"), priority: .low,
          position: 6, createdBy: userId, assigneeIds: mine),
        TaskItem(
          id: "preview-task-7", projectId: officeMoveId,
          title: text("Send the new address to clients", "إرسال العنوان الجديد للعملاء"), status: .done,
          dueAt: day(0, at: 9), position: 7, createdBy: userId, updatedAt: now, assigneeIds: mine),
      ]

      return TasksCopy(
        me: team.first { $0.id == userId }, myTasks: tasks, projects: projects, team: team,
        notifications: notifications)
    }

    /// The models without a public initialiser, read as the database would send them.
    private static func decode<Value: Decodable>(_ type: Value.Type, _ rows: [[String: Any]]) -> Value? {
      guard let data = try? JSONSerialization.data(withJSONObject: rows) else { return nil }
      return try? MahamJSON.decoder().decode(type, from: data)
    }
  }

  /// Maham Tasks' copy, in the shape `TasksStore` keeps it (its `Cached`, field
  /// for field). If that shape changes, the Tasks department starts empty here.
  private struct TasksCopy: Encodable {
    var me: TasksProfile?
    var myTasks: [TaskItem]
    var projects: [TasksProject]
    var team: [TasksProfile]
    var notifications: [TaskNotification]
  }

  /// Answers every request as if the iPhone were offline: preview mode never
  /// reaches the network.
  private struct OfflineTransport: HTTPTransport {
    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
      throw MahamError.offline
    }
  }
#endif
