import MahamKit
import SwiftUI

/// The first tab: your day across both departments — the Apple Intelligence
/// briefing, your tasks for today, and how the company stands.
struct HomeView: View {
  @Environment(AppModel.self) private var model
  @State private var showingSettings = false
  @State private var showingNewTask = false

  var body: some View {
    NavigationStack {
      ScrollView {
        VStack(alignment: .leading, spacing: 18) {
          header
          BriefingCard()
          TasksGlance()
          BusinessGlance()
        }
        .padding(.horizontal)
        .padding(.bottom, 32)
        .frame(maxWidth: 900)
        .frame(maxWidth: .infinity)
      }
      .mahamScreen()
      .navigationTitle("Home")
      .toolbarTitleDisplayMode(.inlineLarge)
      .toolbar {
        ToolbarItem(placement: .topBarLeading) {
          Button("Settings", systemImage: "person.crop.circle") { showingSettings = true }
        }
        ToolbarItem(placement: .topBarTrailing) {
          Button("New task", systemImage: "plus") { showingNewTask = true }
            .buttonStyle(.glassProminent)
            .disabled(model.tasks.notInTasks)
        }
      }
      .refreshable { await model.refreshAll() }
      .taskDestinations()
      .businessDestinations()
      .sheet(isPresented: $showingSettings) { SettingsView() }
      .sheet(isPresented: $showingNewTask) { TaskEditorView() }
    }
  }

  private var header: some View {
    VStack(alignment: .leading, spacing: 4) {
      Text(Date.now.formatted(.dateTime.weekday(.wide).day().month(.wide)))
        .font(.subheadline.weight(.semibold))
        .foregroundStyle(.secondary)
        .textCase(.uppercase)
      Text(greeting)
        .font(.title.bold())
    }
    .padding(.top, 4)
    .accessibilityElement(children: .combine)
  }

  private var greeting: String {
    let hour = Calendar.current.component(.hour, from: .now)
    let name = model.firstName
    switch hour {
    case 5..<12: return name.map { String(localized: "Good morning, \($0)") } ?? String(localized: "Good morning")
    case 12..<17: return name.map { String(localized: "Good afternoon, \($0)") } ?? String(localized: "Good afternoon")
    default: return name.map { String(localized: "Good evening, \($0)") } ?? String(localized: "Good evening")
    }
  }
}

extension AppModel {
  /// "Sara" from "Sara Ali", for a greeting.
  var firstName: String? {
    guard let name = tasks.me?.fullName, !name.isEmpty else { return nil }
    return name.split(separator: " ").first.map(String.init)
  }
}

/// Today in Maham Tasks: three numbers and what to do first.
private struct TasksGlance: View {
  @Environment(AppModel.self) private var model

  var body: some View {
    let plan = model.tasks.plan
    GlassSection("Maham Tasks", symbol: "checklist") {
      Button("See all") { model.selectedTab = .tasks }
    } content: {
      if model.tasks.notInTasks {
        Text("You're not in Maham Tasks yet. An admin can invite you on tasks.mahamone.com.")
          .font(.subheadline)
          .foregroundStyle(.secondary)
      } else {
        GlassEffectContainer(spacing: 12) {
          HStack(spacing: 12) {
            MetricTile(title: "Overdue", value: "\(plan.overdue.count)", symbol: "exclamationmark.circle", tint: .red)
            MetricTile(title: "Today", value: "\(plan.today.count)", symbol: "sun.max", tint: .blue)
            MetricTile(title: "Done today", value: "\(plan.doneToday.count)", symbol: "checkmark.circle", tint: .green)
          }
        }
        if plan.isClear {
          Label("You're all clear for today.", systemImage: "sparkles")
            .font(.subheadline.weight(.medium))
            .foregroundStyle(.secondary)
            .padding(.vertical, 4)
        } else {
          VStack(spacing: 4) {
            ForEach(plan.focus.prefix(5)) { task in
              NavigationLink(value: task) {
                TaskRow(task: task)
                  .contentShape(.rect)
              }
              .buttonStyle(.plain)
              if task.id != plan.focus.prefix(5).last?.id { Divider() }
            }
          }
          if plan.focus.count > 5 {
            Button("\(plan.focus.count - 5) more for today") { model.open(.today) }
              .font(.subheadline.weight(.medium))
          }
        }
      }
    }
  }
}

/// The company at a glance: what's owed, what's late, what expires soon.
private struct BusinessGlance: View {
  @Environment(AppModel.self) private var model

  var body: some View {
    let business = model.business
    GlassSection("Maham One", symbol: "building.2") {
      Button("See all") { model.selectedTab = .business }
    } content: {
      if let company = business.company {
        HStack(spacing: 8) {
          Text(company.name).font(.subheadline.weight(.semibold))
          Text(company.role.label)
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(.secondary.opacity(0.12), in: .capsule)
        }
        let summary = business.summary
        GlassEffectContainer(spacing: 12) {
          HStack(spacing: 12) {
            MetricTile(
              title: "Receivable", value: business.format(summary.receivable),
              symbol: "banknote", tint: .indigo, detail: String(localized: "\(summary.openInvoices) open"))
            MetricTile(
              title: "Overdue", value: "\(summary.overdueInvoices)",
              symbol: "clock.badge.exclamationmark", tint: .red,
              detail: summary.overdueInvoices > 0 ? business.format(summary.overdueAmount) : nil)
          }
        }
        if !summary.expiringSoon.isEmpty {
          Label(
            "\(summary.expiringSoon.count) documents expire within 30 days",
            systemImage: "calendar.badge.exclamationmark"
          )
          .font(.subheadline.weight(.medium))
          .foregroundStyle(.orange)
        }
      } else if business.loadedOnce {
        Text("You're not in a company yet. The owner can invite you on mahamone.com.")
          .font(.subheadline)
          .foregroundStyle(.secondary)
      } else {
        ProgressView().frame(maxWidth: .infinity)
      }
    }
  }
}
