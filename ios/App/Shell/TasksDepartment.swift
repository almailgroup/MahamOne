import SwiftUI

/// Maham Tasks, the native app's second department: today's Tasks screens,
/// full screen, with the app switcher in their toolbar to go back to Maham One.
struct TasksDepartment: View {
  var body: some View {
    TasksRootView()
      .systemDesign()
  }
}

/// The start of Maham Tasks' toolbar: the app switcher (`LayoutGrid`), the
/// inbox and the iPhone's settings, which the department carries until its
/// own parity stage. Outside the shell (no app switcher) it shows nothing.
struct TasksDepartmentButtons: View {
  @Environment(AppModel.self) private var model
  @Environment(SuiteState.self) private var suite: SuiteState?
  @Environment(ShellChrome.self) private var chrome: ShellChrome?
  @State private var switcherOpen = false
  @State private var showingInbox = false
  @State private var showingSettings = false

  var body: some View {
    if suite != nil {
      HStack(spacing: 4) {
        Button {
          switcherOpen = true
        } label: {
          IconView(.layoutGrid, size: 20)
            .frame(width: 32, height: 32)
            .contentShape(Rectangle())
        }
        .accessibilityLabel(Text(t("Switch app")))
        .anchoredPanel(
          isPresented: $switcherOpen, alignment: .start, width: min(368, (chrome?.screenSize.width ?? 390) - 24)
        ) {
          AppSwitcherPanel()
        }
        Button {
          showingInbox = true
        } label: {
          Image(systemName: model.tasks.unreadCount > 0 ? "tray.full" : "tray")
            .frame(width: 32, height: 32)
            .contentShape(Rectangle())
        }
        .accessibilityLabel(Text("Inbox"))
        Button {
          showingSettings = true
        } label: {
          Image(systemName: "gearshape")
            .frame(width: 32, height: 32)
            .contentShape(Rectangle())
        }
        .accessibilityLabel(Text("Settings"))
      }
      .sheet(isPresented: $showingInbox) { InboxView() }
      .sheet(isPresented: $showingSettings) { SettingsView() }
      .onChange(of: model.pendingLink, initial: true) { _, link in
        if link == .inbox { showingInbox = true }
      }
    }
  }
}
