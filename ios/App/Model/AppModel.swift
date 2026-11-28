import LocalAuthentication
import MahamKit
import Observation
import SwiftUI

/// The tabs of the app. Home and Search are the app's own; Business is the
/// Maham One department, Tasks the Maham Tasks one.
enum AppTab: String, Hashable, CaseIterable {
  case home, business, tasks, inbox, search
}

/// A short message at the bottom of the screen.
struct Toast: Identifiable, Equatable {
  enum Kind { case success, error }
  let id = UUID()
  let kind: Kind
  let message: String
}

/// The whole app's state: who is signed in, whether the app is locked, the
/// two departments' stores, and where to go next.
@MainActor
@Observable
final class AppModel {
  enum Phase: Equatable {
    /// The publishable key isn't in the build (Config/Local.xcconfig).
    case notConfigured
    case starting
    case signedOut
    /// Password accepted; the authenticator app's code is next.
    case secondStep
    /// Signed in, waiting for Face ID.
    case locked
    case ready
  }

  private(set) var phase: Phase = .starting
  private(set) var session: AuthSession?
  let services: AppServices?
  let tasks: TasksStore
  let business: BusinessStore
  /// Every record of the company on screen, kept in step with the cloud.
  let one: OneData

  var selectedTab: AppTab = .home
  /// A link the shell should follow once it is on screen.
  var pendingLink: DeepLink?
  var toast: Toast?

  /// Face ID when the app comes back after a while.
  var lockEnabled: Bool {
    didSet { UserDefaults.standard.set(lockEnabled, forKey: Preferences.lockKey) }
  }
  private var backgroundedAt: Date?

  #if DEBUG
    /// The one model, shared by every window, the delegate and the intents.
    /// Preview mode (App/Preview): on the made-up services, which never reach the network.
    static let shared = PreviewMode.isOn ? AppModel(services: PreviewMode.services) : AppModel()
  #else
    /// The one model, shared by every window, the delegate and the intents.
    static let shared = AppModel()
  #endif

  init(services: AppServices? = AppServices.shared) {
    self.services = services
    tasks = TasksStore(services: services)
    business = BusinessStore(services: services)
    one = OneData(services: services)
    lockEnabled = UserDefaults.standard.object(forKey: Preferences.lockKey) as? Bool ?? true
    tasks.onError = { [weak self] in self?.show($0) }
    business.onError = { [weak self] in self?.show($0) }
    Navigator.handler = { [weak self] in self?.open($0) }
  }

  // MARK: Starting

  private var starting: Task<Void, Never>?

  /// Starts once, however many times it is asked (launch, a reminder's
  /// button, a background refresh).
  func ensureStarted() async {
    if let starting { return await starting.value }
    let task = Task { await start() }
    starting = task
    await task.value
  }

  private func start() async {
    #if DEBUG
      // Preview mode (App/Preview): signed in as the made-up person, no lock, no refresh.
      if PreviewMode.isOn, let services {
        session = await services.auth.currentSession
        phase = .ready
        return
      }
    #endif
    guard let services else {
      phase = .notConfigured
      return
    }
    guard let saved = await services.auth.currentSession else {
      phase = .signedOut
      return
    }
    session = saved
    if saved.user.verifiedTOTP != nil, !saved.signedInWithSecondStep {
      phase = .secondStep
      return
    }
    phase = lockEnabled && Biometrics.isAvailable ? .locked : .ready
    if phase == .ready { await refreshAll() }
  }

  /// Both departments at once (pull to refresh on Home, coming back).
  func refreshAll() async {
    async let tasksLoad: Void = tasks.refresh()
    async let businessLoad: Void = business.refresh()
    async let oneLoad: Void = one.sync()
    _ = await (tasksLoad, businessLoad, oneLoad)
  }

  /// Opens the company on screen's records (downloading them the first time).
  func openCompanyData() {
    guard let company = business.company, let userId = session?.user.id else {
      one.close()
      return
    }
    #if DEBUG
      if PreviewMode.isOn {
        one.openPreview(company, userId: userId, records: PreviewRecords.all(company: company))
        return
      }
    #endif
    one.open(company, userId: userId, authorName: session?.user.authorName ?? "")
  }

  // MARK: Signing in and out

  func signIn(email: String, password: String) async throws {
    guard let services else { return }
    switch try await services.auth.signIn(email: email, password: password) {
    case .signedIn(let session):
      self.session = session
      phase = .ready
      await signedIn()
    case .needsSecondStep(let session):
      self.session = session
      phase = .secondStep
    }
  }

  func verify(code: String) async throws {
    guard let services else { return }
    session = try await services.auth.verifySecondStep(code: code)
    phase = .ready
    await signedIn()
  }

  private func signedIn() async {
    await refreshAll()
    if Preferences.reminders { await Reminders.requestPermission() }
    // Due-date reminders need the permission first; schedule them now.
    SystemSync.tasksChanged(tasks.myTasks, plan: tasks.plan, projects: tasks.projects)
  }

  func sendPasswordReset(email: String) async throws {
    try await services?.auth.sendPasswordReset(email: email)
  }

  func signOut() async {
    let userId = session?.user.id
    await services?.auth.signOut()
    services?.cache.clear()
    tasks.reset()
    business.reset()
    if let userId { one.removeAll(userId: userId) } else { one.close() }
    SystemSync.signedOut()
    session = nil
    selectedTab = .home
    phase = .signedOut
  }

  // MARK: The lock

  func unlock() async {
    if await Biometrics.authenticate(reason: String(localized: "Unlock Maham One")) {
      phase = .ready
      await refreshAll()
    }
  }

  func scenePhaseChanged(_ scenePhase: ScenePhase) {
    switch scenePhase {
    case .background:
      backgroundedAt = Date()
    case .active:
      // Locked again after five minutes away.
      if phase == .ready, lockEnabled, Biometrics.isAvailable, let away = backgroundedAt,
        Date().timeIntervalSince(away) > 300
      {
        phase = .locked
      } else if phase == .ready, let away = backgroundedAt, Date().timeIntervalSince(away) > 60 {
        Task { await refreshAll() }
      } else if phase == .ready {
        Task { await one.appBecameActive() }
      }
      backgroundedAt = nil
    default:
      break
    }
  }

  // MARK: Away from the screen

  /// iOS woke the app to refresh: tasks only (for the widgets and the
  /// reminders), and only with a session. The lock doesn't matter here,
  /// nothing is shown.
  func backgroundRefresh() async {
    await ensureStarted()
    guard phase == .ready || phase == .locked else { return }
    await tasks.refresh()
  }

  /// The reminder's Mark Done button.
  func completeFromReminder(_ id: String) async {
    await ensureStarted()
    guard phase == .ready || phase == .locked else { return }
    do {
      guard let task = try await tasks.task(id), !task.isDone else { return }
      let updated = try await tasks.complete(task)
      confirm(updated.isDone ? "Marked done." : "Sent for review.")
    } catch {
      show(error)
    }
  }

  // MARK: Going places

  func open(_ link: DeepLink) {
    switch link {
    case .today, .newTask, .task, .project: selectedTab = .tasks
    case .invoice, .client: selectedTab = .business
    case .inbox: selectedTab = .inbox
    }
    pendingLink = link
  }

  func open(url: URL) {
    if let link = DeepLink(url: url) { open(link) }
  }

  // MARK: Messages

  func show(_ error: Error) {
    let message = (error as? MahamError)?.message ?? error.localizedDescription
    if (error as? MahamError) == .sessionExpired {
      Task { await signOut() }
    }
    toast = Toast(kind: .error, message: message)
  }

  func confirm(_ message: String) {
    toast = Toast(kind: .success, message: message)
  }
}

/// Face ID, Touch ID or the passcode.
enum Biometrics {
  static var isAvailable: Bool {
    LAContext().canEvaluatePolicy(.deviceOwnerAuthentication, error: nil)
  }

  static var kind: LABiometryType {
    let context = LAContext()
    _ = context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: nil)
    return context.biometryType
  }

  static func authenticate(reason: String) async -> Bool {
    let context = LAContext()
    context.localizedFallbackTitle = String(localized: "Use Passcode")
    do {
      return try await context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: reason)
    } catch {
      return false
    }
  }
}
