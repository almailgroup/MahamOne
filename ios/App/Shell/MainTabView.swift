import MahamKit
import SwiftUI

/// The app once you're in: Home, the two departments (Maham One and Maham
/// Tasks), the inbox, and search. A tab bar of Liquid Glass on iPhone that
/// shrinks as you scroll; a sidebar on iPad.
struct MainTabView: View {
  @Environment(AppModel.self) private var model

  var body: some View {
    @Bindable var model = model
    TabView(selection: $model.selectedTab) {
      Tab("Home", systemImage: "house", value: AppTab.home) {
        HomeView()
      }

      TabSection("Departments") {
        Tab("Maham One", systemImage: "building.2", value: AppTab.business) {
          BusinessRootView()
        }
        Tab("Maham Tasks", systemImage: "checklist", value: AppTab.tasks) {
          TasksRootView()
        }
        .badge(model.tasks.plan.overdue.count)
      }

      Tab("Inbox", systemImage: "tray", value: AppTab.inbox) {
        InboxView()
      }
      .badge(model.tasks.unreadCount)

      Tab(value: AppTab.search, role: .search) {
        SearchView()
      }
    }
    .tabViewStyle(.sidebarAdaptable)
    .tabBarMinimizeBehavior(.onScrollDown)
    .haptic(.selection, trigger: model.selectedTab)
  }
}
