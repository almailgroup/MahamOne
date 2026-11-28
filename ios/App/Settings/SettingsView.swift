import AppIntents
import MahamKit
import SwiftUI
import UIKit
import UserNotifications

/// You, this iPhone's settings, and signing out.
struct SettingsView: View {
  @Environment(AppModel.self) private var model
  @Environment(\.dismiss) private var dismiss
  @Environment(\.openURL) private var openURL
  @AppStorage(Preferences.remindersKey) private var reminders = true
  @AppStorage(Preferences.spotlightKey) private var spotlight = true
  @AppStorage(Preferences.briefingKey) private var briefing = true
  @State private var confirmingSignOut = false
  @State private var notificationsDenied = false

  var body: some View {
    @Bindable var model = model
    NavigationStack {
      Form {
        Section { account }

        if model.business.companies.count > 1 {
          Section("Company") {
            Picker("Company", selection: companyBinding) {
              ForEach(model.business.companies) { company in
                Text(company.name).tag(Optional(company.id))
              }
            }
          }
        }

        Section {
          if Biometrics.isAvailable {
            Toggle(isOn: $model.lockEnabled) {
              Label(lockTitle, systemImage: Biometrics.kind == .touchID ? "touchid" : "faceid")
            }
          }
        } header: {
          Text("Security")
        } footer: {
          Text("Asks again when you come back after five minutes away.")
        }

        Section {
          Toggle(isOn: $reminders) {
            Label("Due-date reminders", systemImage: "bell.badge")
          }
          if notificationsDenied {
            Button("Allow notifications in Settings") {
              if let url = URL(string: UIApplication.openNotificationSettingsURLString) { openURL(url) }
            }
          }
        } header: {
          Text("Notifications")
        } footer: {
          Text("A reminder when one of your tasks is due, with Mark Done on it. Made on this iPhone.")
        }

        Section {
          Toggle(isOn: $briefing) {
            Label("Day briefing", systemImage: "sparkles")
          }
        } header: {
          Text("Apple Intelligence")
        } footer: {
          Text("Summarizes your day with Apple Intelligence on this iPhone. Nothing is sent anywhere.")
        }

        Section {
          Toggle(isOn: $spotlight) {
            Label("Show in Spotlight", systemImage: "magnifyingglass")
          }
          ShortcutsLink()
            .shortcutsLinkStyle(.automaticOutline)
        } header: {
          Text("Search and Siri")
        } footer: {
          Text("Your open tasks and the company's clients appear in the iPhone's search. Ask Siri to add a task or what's due today.")
        }

        Section {
          Button("Sign Out", role: .destructive) { confirmingSignOut = true }
        } footer: {
          Text("Version \(Bundle.main.version)")
            .frame(maxWidth: .infinity)
            .padding(.top, 12)
        }
      }
      .mahamScreen()
      .navigationTitle("Settings")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .confirmationAction) {
          Button("Close", systemImage: "xmark") { dismiss() }
        }
      }
      .confirmationDialog("Sign out of Maham One?", isPresented: $confirmingSignOut, titleVisibility: .visible) {
        Button("Sign Out", role: .destructive) {
          dismiss()
          Task { await model.signOut() }
        }
      } message: {
        Text("Everything the app kept on this iPhone is removed.")
      }
      .onChange(of: reminders) { _, on in
        if on {
          Task {
            let allowed = await Reminders.requestPermission()
            notificationsDenied = !allowed
            resync()
          }
        } else {
          SystemSync.remindersTurnedOff()
        }
      }
      .onChange(of: spotlight) { _, on in
        if on { resync() } else { SystemSync.spotlightTurnedOff() }
      }
      .task {
        let status = await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
        notificationsDenied = reminders && status == .denied
      }
    }
  }

  private var account: some View {
    HStack(spacing: 14) {
      if let me = model.tasks.me {
        AvatarView(profile: me, size: 52)
      } else {
        Image(systemName: "person.crop.circle.fill")
          .font(.system(size: 48))
          .foregroundStyle(.secondary)
      }
      VStack(alignment: .leading, spacing: 3) {
        Text(model.tasks.me?.displayName ?? model.session?.user.email ?? "")
          .font(.headline)
        if let email = model.session?.user.email {
          Text(email).font(.subheadline).foregroundStyle(.secondary)
        }
        if let title = model.tasks.me?.jobTitle, !title.isEmpty {
          Text(title).font(.caption).foregroundStyle(.tertiary)
        }
      }
    }
    .padding(.vertical, 4)
    .accessibilityElement(children: .combine)
  }

  private var companyBinding: Binding<String?> {
    Binding(
      get: { model.business.company?.id },
      set: { id in
        if let company = model.business.companies.first(where: { $0.id == id }) {
          model.business.select(company)
        }
      })
  }

  private var lockTitle: LocalizedStringKey {
    switch Biometrics.kind {
    case .touchID: "Lock with Touch ID"
    case .opticID: "Lock with Optic ID"
    default: "Lock with Face ID"
    }
  }

  private func resync() {
    SystemSync.tasksChanged(model.tasks.myTasks, plan: model.tasks.plan, projects: model.tasks.projects)
    SystemSync.businessChanged(
      clients: model.business.clients, invoices: model.business.invoices, expiries: model.business.expiries)
  }
}

extension Bundle {
  /// "1.0.0 (1)".
  var version: String {
    let short = infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
    let build = infoDictionary?["CFBundleVersion"] as? String ?? "1"
    return "\(short) (\(build))"
  }
}
