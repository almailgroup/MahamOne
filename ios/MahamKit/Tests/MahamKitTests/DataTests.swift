import Foundation
import Testing

@testable import MahamKit

private func database(_ fake: FakeTransport) -> DatabaseClient {
  let auth = AuthService(config: testConfig, transport: fake, store: MemorySessionStore(signedInSession()))
  return DatabaseClient(auth: auth, transport: fake)
}

private let taskJSON = #"""
  {"id":"t1","project_id":null,"title":"Renew the trade licence","description":null,
   "status":"in_progress","priority":"high","due_at":"2026-11-24T09:00:00+00:00",
   "follow_up_at":null,"follow_up_note":null,"position":2048,"created_by":"user-1",
   "deleted_at":null,"repeat_every":null,"repeat_interval":1,
   "created_at":"2026-11-20T08:00:00.123456+00:00","updated_at":"2026-11-23T08:00:00+00:00",
   "assignees":[{"user_id":"user-1"},{"user_id":"user-2"}]}
  """#

@Suite("Maham Tasks")
struct TasksTests {
  @Test("reads a task with everyone it is assigned to")
  func decodeTask() throws {
    let task = try MahamJSON.decoder().decode(TaskItem.self, from: Data(taskJSON.utf8))
    #expect(task.status == .inProgress)
    #expect(task.priority == .high)
    #expect(task.assigneeIds == ["user-1", "user-2"])
    #expect(task.position == 2048)
    #expect(task.dueAt == MahamDates.parseTimestamp("2026-11-24T09:00:00Z"))
  }

  @Test("signing in accepts an invite, as on the website")
  func join() async throws {
    let joined = Flag()
    let fake = FakeTransport { request in
      switch request.path {
      case "/rest/v1/profiles":
        // No profile until `join` has run.
        joined.take()
          ? .init(status: 200, body: "[]")
          : .init(status: 200, body: #"[{"id":"user-1","email":"noor@example.com","full_name":"Noor Example","avatar_url":null,"role":"member","job_title":null}]"#)
      case "/rest/v1/rpc/join": .init(status: 200, body: "true")
      default: .init(status: 404, body: "{}")
      }
    }
    let repo = TasksRepository(db: database(fake))
    let me = try await repo.me()
    #expect(me.displayName == "Noor Example")
    #expect(me.initials == "NE")
    #expect(fake.sent.map(\.path) == ["/rest/v1/profiles", "/rest/v1/rpc/join", "/rest/v1/profiles"])
    #expect(fake.sent[1].value(forHTTPHeaderField: "Content-Profile") == "tasks")
  }

  @Test("an account nobody invited is told so")
  func notInvited() async throws {
    let fake = FakeTransport { request in
      request.path.hasSuffix("join") ? .init(status: 200, body: "false") : .init(status: 200, body: "[]")
    }
    await #expect(throws: MahamError.notInTasks) { try await TasksRepository(db: database(fake)).me() }
  }

  @Test("my tasks are those assigned to me, with all their assignees")
  func myTasks() async throws {
    let fake = FakeTransport { _ in .init(status: 200, body: "[\(taskJSON)]") }
    let tasks = try await TasksRepository(db: database(fake)).myTasks(userId: "user-1")
    #expect(tasks.count == 1)
    let query = try #require(fake.sent.first?.query.removingPercentEncoding)
    #expect(query.contains("mine:task_assignments!inner()"))
    #expect(query.contains("assignees:task_assignments(user_id)"))
    #expect(query.contains("mine.user_id=eq.user-1"))
    #expect(query.contains("deleted_at=is.null"))
  }

  @Test("a new task goes to the end of its column, with its people and steps")
  func create() async throws {
    let fake = FakeTransport { request in
      switch (request.httpMethod, request.path) {
      case ("GET", "/rest/v1/tasks"): .init(status: 200, body: #"[{"position":4096}]"#)
      case ("POST", "/rest/v1/tasks"): .init(status: 201, body: "[\(taskJSON)]")
      default: .init(status: 201, body: "")
      }
    }
    var draft = TaskDraft(title: "  Renew the trade licence ", priority: .high)
    draft.assigneeIds = ["user-2"]
    draft.steps = ["Collect the papers", "  ", "Pay the fee"]
    _ = try await TasksRepository(db: database(fake)).createTask(draft, by: "user-1")

    let posts = fake.sent.filter { $0.httpMethod == "POST" }
    #expect(posts.map(\.path) == ["/rest/v1/tasks", "/rest/v1/task_assignments", "/rest/v1/task_checklist_items"])
    let task = posts[0].bodyText
    #expect(task.contains(#""title":"Renew the trade licence""#))
    #expect(task.contains(#""position":5120"#))
    #expect(task.contains(#""project_id":null"#))
    #expect(task.contains(#""description":null"#))
    #expect(task.contains(#""created_by":"user-1""#))
    #expect(posts[1].bodyText.contains(#""user_id":"user-2""#))
    #expect(posts[2].bodyText.contains("Collect the papers"))
    #expect(!posts[2].bodyText.contains(#""content":"  ""#))
  }

  @Test("a title is needed, as on the website")
  func validation() {
    #expect(TaskDraft(title: "  ").problem != nil)
    #expect(TaskDraft(title: String(repeating: "x", count: 201)).problem != nil)
    #expect(TaskDraft(title: "Call the bank").problem == nil)
  }

  @Test("a status the rules refuse says so")
  func refused() async throws {
    let fake = FakeTransport { _ in .init(status: 200, body: "[]") }
    await #expect(throws: MahamError.self) {
      try await TasksRepository(db: database(fake)).setStatus("t1", to: .done)
    }
  }

  @Test("the day's plan: late, today, coming up, no date")
  func plan() throws {
    let now = try #require(MahamDates.parseTimestamp("2026-11-24T09:00:00Z"))  // 12:00 in Kuwait
    func task(_ id: String, due: String?, status: TaskStatus = .todo) -> TaskItem {
      TaskItem(
        id: id, title: id, status: status, dueAt: due.flatMap(MahamDates.parseTimestamp),
        updatedAt: now)
    }
    let plan = DayPlan(
      tasks: [
        task("yesterday", due: "2026-11-23T10:00:00Z"),
        task("this-morning", due: "2026-11-24T06:00:00Z"),
        task("this-evening", due: "2026-11-24T16:00:00Z"),
        task("tomorrow", due: "2026-11-25T10:00:00Z"),
        task("someday", due: nil),
        task("finished", due: "2026-11-24T06:00:00Z", status: .done),
      ], now: now)
    #expect(plan.overdue.map(\.id) == ["yesterday", "this-morning"])
    #expect(plan.today.map(\.id) == ["this-evening"])
    #expect(plan.upcoming.map(\.id) == ["tomorrow"])
    #expect(plan.someday.map(\.id) == ["someday"])
    #expect(plan.doneToday.map(\.id) == ["finished"])
    #expect(plan.focus.count == 3)

    let snapshot = TodaySnapshot(plan: plan, now: now)
    #expect(snapshot.overdueCount == 2)
    #expect(snapshot.items.first?.overdue == true)
  }
}

private let invoiceJSON = #"""
  {"id":"d1","companyId":"c1","type":"invoice","number":"INV-2026-0042","status":"partial",
   "clientId":"k1","issueDate":"2026-10-01","dueDate":"2026-10-31","currency":"KWD",
   "items":[{"id":"l1","kind":"item","name":"Installation","description":"","quantity":2,"unit":"day","unitPrice":75.5}],
   "totals":{"subtotal":151,"discount":0,"taxTotal":0,"total":151,"paid":51,"balance":100},
   "notes":"","poNumber":"PO-7","somethingNewer":{"a":1}}
  """#

@Suite("Maham One")
struct OneTests {
  @Test("reads an invoice, ignoring fields it doesn't know")
  func invoice() throws {
    let doc = try MahamJSON.decoder().decode(SalesDocument.self, from: Data(invoiceJSON.utf8))
    #expect(doc.number == "INV-2026-0042")
    #expect(doc.status == .partial)
    #expect(doc.items.first?.amount == 151)
    #expect(doc.isOpen)
    #expect(doc.isOverdue(today: LocalDate(year: 2026, month: 11, day: 24)))
    #expect(doc.daysOverdue(today: LocalDate(year: 2026, month: 11, day: 24)) == 24)
  }

  @Test("a record written by an older web app still reads")
  func sparse() throws {
    let client = try MahamJSON.decoder().decode(
      Client.self,
      from: Data(#"{"id":"k1","name":"Gulf Pearl Hotel","contacts":[{"name":"Sara","phone":"+965 5000 0000","primary":true}]}"#.utf8))
    #expect(client.bestPhone == "+965 5000 0000")
    #expect(client.bestEmail == nil)
    #expect(client.isCustomer)
  }

  @Test("the business summary: what is owed, what is late, what expires")
  func summary() throws {
    let today = LocalDate(year: 2026, month: 11, day: 24)
    let overdue = try MahamJSON.decoder().decode(SalesDocument.self, from: Data(invoiceJSON.utf8))
    var paid = overdue
    paid.status = .paid
    paid.totals.balance = 0
    var thisMonth = overdue
    thisMonth.issueDate = LocalDate(year: 2026, month: 11, day: 2)
    thisMonth.dueDate = LocalDate(year: 2026, month: 12, day: 2)
    thisMonth.totals = DocumentTotals(total: 200, balance: 200)

    let expiries = [
      Expiry(id: "e1", title: "Trade licence", owner: "", date: today.adding(days: 10)),
      Expiry(id: "e2", title: "Passport", owner: "Noor", date: today.adding(days: 90)),
    ]
    let summary = BusinessSummary(
      invoices: [overdue, paid, thisMonth], expiries: expiries, currency: "KWD", today: today)
    #expect(summary.openInvoices == 2)
    #expect(summary.receivable == 300)
    #expect(summary.overdueInvoices == 1)
    #expect(summary.overdueAmount == 100)
    #expect(summary.invoicedThisMonth == 200)
    #expect(summary.expiringSoon.map(\.id) == ["e1"])
  }

  @Test("records are read for one company and one kind")
  func records() async throws {
    let fake = FakeTransport { _ in .init(status: 200, body: #"[{"id":"d1","rev":7,"data":\#(invoiceJSON)}]"#) }
    let invoices = try await OneRepository(db: database(fake)).invoices(company: "c1")
    #expect(invoices.count == 1)
    let query = try #require(fake.sent.first?.query.removingPercentEncoding)
    #expect(query.contains("company_id=eq.c1"))
    #expect(query.contains("tbl=eq.documents"))
    #expect(query.contains("data->>type=eq.invoice"))
    #expect(fake.sent.first?.value(forHTTPHeaderField: "Accept-Profile") == "public")
  }

  @Test("employees' papers become expiries, soonest first")
  func papers() throws {
    let employee = try MahamJSON.decoder().decode(
      Employee.self,
      from: Data(#"{"id":"e1","name":"Noor","status":"active","passportExpiry":"2027-01-10","civilIdExpiry":"2026-12-01"}"#.utf8))
    let list = expiries(documents: [], employees: [employee])
    #expect(list.map(\.title) == ["Civil ID", "Passport"])
  }

  @Test("money as Maham One shows it")
  func money() {
    #expect(Money.fractionDigits("KWD") == 3)
    #expect(Money.fractionDigits("USD") == 2)
    let text = Money.format(1234.5, currency: "KWD", locale: Locale(identifier: "en_US"))
    #expect(text.contains("1,234.500"))
  }

  @Test("the team's changes are only for those allowed")
  func updates() async throws {
    let fake = FakeTransport { _ in .init(status: 403, body: #"{"code":"42501","message":"not allowed"}"#) }
    let events = try await OneRepository(db: database(fake)).updates(company: "c1")
    #expect(events.isEmpty)
  }
}

@Suite("Offline store")
struct StoreTests {
  @Test("keeps what it is given, and forgets it all on signing out")
  func cache() throws {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    let cache = DiskCache(directory: dir)
    let task = try MahamJSON.decoder().decode(TaskItem.self, from: Data(taskJSON.utf8))
    cache.save([task], as: "my-tasks/user-1")
    #expect(cache.load([TaskItem].self, as: "my-tasks/user-1") == [task])
    cache.clear()
    #expect(cache.load([TaskItem].self, as: "my-tasks/user-1") == nil)
  }
}
