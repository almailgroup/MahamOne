import BackgroundTasks
import CoreSpotlight
import MahamKit
import SwiftUI
import UserNotifications

@main
struct MahamOneApp: App {
  @UIApplicationDelegateAdaptor(AppDelegate.self) private var delegate
  @Environment(\.scenePhase) private var scenePhase
  private let model = AppModel.shared

  var body: some Scene {
    WindowGroup {
      RootView()
        .environment(model)
        .onOpenURL { model.open(url: $0) }
        .onContinueUserActivity(CSSearchableItemActionType) { activity in
          if let id = activity.userInfo?[CSSearchableItemActivityIdentifier] as? String,
            let link = DeepLink(string: id)
          {
            model.open(link)
          }
        }
        .onContinueUserActivity(ActivityType.task) { activity in
          if let id = activity.userInfo?[ActivityType.idKey] as? String { model.open(.task(id)) }
        }
        .onContinueUserActivity(ActivityType.invoice) { activity in
          if let id = activity.userInfo?[ActivityType.idKey] as? String { model.open(.invoice(id)) }
        }
        .onContinueUserActivity(ActivityType.client) { activity in
          if let id = activity.userInfo?[ActivityType.idKey] as? String { model.open(.client(id)) }
        }
    }
    .onChange(of: scenePhase) { _, phase in
      model.scenePhaseChanged(phase)
      if phase == .background { BackgroundRefresh.schedule() }
    }
    .backgroundTask(.appRefresh(BackgroundRefresh.identifier)) {
      await BackgroundRefresh.run()
    }
  }
}

/// The app's delegate: starts the model, and answers the reminders' buttons.
final class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
  private var model: AppModel { AppModel.shared }

  func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
  ) -> Bool {
    UNUserNotificationCenter.current().delegate = self
    Reminders.registerCategories()
    Task { await model.ensureStarted() }
    return true
  }

  /// A reminder while the app is open still shows, as a banner.
  nonisolated func userNotificationCenter(
    _ center: UNUserNotificationCenter, willPresent notification: UNNotification
  ) async -> UNNotificationPresentationOptions {
    [.banner, .list, .sound]
  }

  nonisolated func userNotificationCenter(
    _ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse
  ) async {
    let action = response.actionIdentifier
    let info = response.notification.request.content.userInfo
    let taskId = info["taskId"] as? String
    let title = info["title"] as? String ?? ""
    let link = (info["link"] as? String).flatMap(DeepLink.init(string:))
    await MainActor.run {
      switch action {
      case Reminders.doneAction:
        if let taskId { Task { await AppModel.shared.completeFromReminder(taskId) } }
      case Reminders.snoozeAction:
        if let taskId { Task { await Reminders.snooze(taskId: taskId, title: title) } }
      default:
        if let link { AppModel.shared.open(link) }
      }
    }
  }
}

/// A refresh now and then while the app is closed, so the widgets and the
/// reminders keep up with what the team changed.
enum BackgroundRefresh {
  static let identifier = "com.almailgroup.mahamone.refresh"

  static func schedule() {
    let request = BGAppRefreshTaskRequest(identifier: identifier)
    request.earliestBeginDate = Date(timeIntervalSinceNow: 30 * 60)
    try? BGTaskScheduler.shared.submit(request)
  }

  @MainActor
  static func run() async {
    schedule()
    await AppModel.shared.backgroundRefresh()
  }
}
