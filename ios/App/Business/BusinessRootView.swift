import MahamKit
import SwiftUI

/// The Maham One tab: the company you're looking at, how it stands, and its
/// invoices, clients, people and expiry dates. View only on iPhone for now.
struct BusinessRootView: View {
  @Environment(AppModel.self) private var model
  @State private var path = NavigationPath()
  /// The company list has been asked for at least once since this appeared.
  @State private var checkedCompanies = false
  /// A link waiting for the records to load before it opens.
  @State private var followingLink: DeepLink?

  init() {}

  var body: some View {
    NavigationStack(path: $path) {
      content
        .navigationTitle("Maham One")
        .toolbar { companyToolbar }
        .navigationDestination(for: BusinessRoute.self) { route in
          BusinessRouteView(route: route)
        }
        .businessDestinations()
    }
    .task { await checkCompanies() }
    .onChange(of: model.pendingLink, initial: true) { _, link in
      follow(link)
    }
    .onChange(of: model.business.selectedCompanyId) { _, _ in
      // What was open belongs to the other company.
      if followingLink == nil { path = NavigationPath() }
    }
  }

  // MARK: Content

  @ViewBuilder
  private var content: some View {
    let business = model.business
    if business.companies.isEmpty {
      ScrollView {
        Group {
          if checkedCompanies, !business.isLoading {
            EmptyState(
              title: "No company yet", symbol: "building.2",
              message: "When someone invites you to their company on mahamone.com, it shows here.")
          } else {
            ProgressView()
          }
        }
        .frame(maxWidth: .infinity)
        .containerRelativeFrame(.vertical)
      }
      .mahamScreen()
      .refreshable {
        await Haptics.refresh()
        await business.refresh()
      }
    } else {
      ScrollView {
        VStack(alignment: .leading, spacing: 18) {
          BusinessCompanyHeader()
          NoticeBanner(text: "View only on iPhone for now — make changes on mahamone.com", symbol: "eye")
          BusinessOverview()
          GlassSection("Invoiced by month", symbol: "chart.bar.xaxis") {
            InvoicedByMonthChart()
          }
          BusinessEntries()
        }
        .padding(.horizontal)
        .padding(.bottom, 32)
        .frame(maxWidth: 900)
        .frame(maxWidth: .infinity)
      }
      .mahamScreen()
      .refreshable {
        await Haptics.refresh()
        await business.refresh()
      }
    }
  }

  @ToolbarContentBuilder
  private var companyToolbar: some ToolbarContent {
    if model.business.companies.count > 1 {
      ToolbarItem(placement: .topBarTrailing) {
        BusinessCompanyMenu()
      }
    }
  }

  /// Asks for the company list once when there is none on this iPhone yet,
  /// so "No company yet" is only said after the server has answered.
  private func checkCompanies() async {
    if model.business.companies.isEmpty { await model.business.refresh() }
    checkedCompanies = true
  }

  // MARK: Links from outside (Spotlight, Handoff, a link)

  private func follow(_ link: DeepLink?) {
    guard let link, followingLink != link else { return }
    switch link {
    case .invoice, .client: break
    default: return  // Another tab's.
    }
    if open(link) {
      model.pendingLink = nil
      return
    }
    // Not loaded yet: refresh, wait for the company to load, try once more.
    followingLink = link
    Task {
      await model.business.refresh()
      // A newly chosen company loads in a task of its own; let it start.
      try? await Task.sleep(for: .milliseconds(150))
      var waited = 0
      while model.business.isLoading, waited < 150 {
        try? await Task.sleep(for: .milliseconds(100))
        waited += 1
      }
      followingLink = nil
      guard model.pendingLink == link else { return }
      model.pendingLink = nil
      if !open(link) {
        model.show(
          MahamError.permission(String(localized: "That isn't in the company on screen, or you can't see it.")))
      }
    }
  }

  /// Shows the record a link names, on top of this tab's home.
  private func open(_ link: DeepLink) -> Bool {
    let business = model.business
    var fresh = NavigationPath()
    switch link {
    case .invoice(let id):
      guard let invoice = business.invoice(id) else { return false }
      fresh.append(invoice)
    case .client(let id):
      guard let client = business.client(id) else { return false }
      fresh.append(client)
    default:
      return false
    }
    path = fresh
    return true
  }
}

// MARK: The company

/// The company's name and your role in it.
private struct BusinessCompanyHeader: View {
  @Environment(AppModel.self) private var model

  var body: some View {
    let business = model.business
    if let company = business.company {
      let base = business.profile.map { $0.name.isEmpty ? company.name : $0.name } ?? company.name
      let name = MahamKit.localName(base, business.profile?.nameAr, arabic: BusinessUI.isArabic)
      HStack(alignment: .center, spacing: 12) {
        VStack(alignment: .leading, spacing: 6) {
          Text(name)
            .font(.title3.weight(.semibold))
            .lineLimit(2)
          HStack(spacing: 8) {
            Text(company.role.label)
              .font(.caption.weight(.semibold))
              .foregroundStyle(.secondary)
              .padding(.horizontal, 8)
              .padding(.vertical, 3)
              .background(Color.secondary.opacity(0.12), in: .capsule)
            if company.members > 1 {
              Text("\(company.members) members")
                .font(.caption)
                .foregroundStyle(.secondary)
            }
          }
        }
        Spacer(minLength: 8)
        if business.isLoading {
          ProgressView()
            .accessibilityLabel(Text("Loading"))
        }
      }
      .padding(.top, 4)
    }
  }
}

/// Switching between the companies you belong to, each with your role.
private struct BusinessCompanyMenu: View {
  @Environment(AppModel.self) private var model
  @State private var picks = 0

  var body: some View {
    let business = model.business
    Menu {
      Section("Switch company") {
        ForEach(business.companies) { company in
          Button {
            guard company.id != business.company?.id else { return }
            business.select(company)
            picks += 1
          } label: {
            if company.id == business.company?.id {
              Label {
                Text(company.name)
                Text(company.role.label)
              } icon: {
                Image(systemName: "checkmark")
              }
            } else {
              Text(company.name)
              Text(company.role.label)
            }
          }
        }
      }
    } label: {
      Label("Switch company", systemImage: "building.2")
    }
    .accessibilityLabel(Text("Switch company"))
    .haptic(.selection, trigger: picks)
  }
}

// MARK: Overview

/// Four numbers, each opening its list.
private struct BusinessOverview: View {
  @Environment(AppModel.self) private var model
  @Environment(\.horizontalSizeClass) private var sizeClass

  var body: some View {
    let business = model.business
    let summary = business.summary
    let today = business.today
    let soon = BusinessUI.visibleExpiries(in: business).filter { $0.daysLeft(today: today) <= 30 }.count
    let month = LocalDate(year: today.year, month: today.month, day: 1).start(in: .current)
      .formatted(.dateTime.month(.wide))
    let columns = Array(repeating: GridItem(.flexible(), spacing: 12), count: sizeClass == .regular ? 4 : 2)
    GlassEffectContainer(spacing: 12) {
      LazyVGrid(columns: columns, spacing: 12) {
        NavigationLink(value: BusinessRoute.invoices(.open)) {
          MetricTile(
            title: "Receivable", value: business.format(summary.receivable), symbol: "banknote",
            tint: .indigo, detail: String(localized: "\(summary.openInvoices) open"))
        }
        NavigationLink(value: BusinessRoute.invoices(.overdue)) {
          MetricTile(
            title: "Overdue", value: "\(summary.overdueInvoices)", symbol: "clock.badge.exclamationmark",
            tint: .red, detail: business.format(summary.overdueAmount))
        }
        NavigationLink(value: BusinessRoute.invoices(.all)) {
          MetricTile(
            title: "Invoiced this month", value: business.format(summary.invoicedThisMonth),
            symbol: "chart.bar.fill", tint: .teal, detail: month)
        }
        NavigationLink(value: BusinessRoute.expiries) {
          MetricTile(
            title: "Expiring soon", value: "\(soon)", symbol: "calendar.badge.exclamationmark",
            tint: .orange, detail: String(localized: "Within 30 days"))
        }
      }
      .buttonStyle(.plain)
    }
  }
}

// MARK: The lists

private struct BusinessEntry: Identifiable {
  let route: BusinessRoute
  let title: LocalizedStringKey
  let symbol: String
  let tint: Color
  let count: Int

  var id: BusinessRoute { route }
}

/// Invoices, clients, people (for the roles that see them), expiry dates and
/// the team's updates.
private struct BusinessEntries: View {
  @Environment(AppModel.self) private var model

  var body: some View {
    let entries = makeEntries()
    GlassSection("Records", symbol: "square.stack.3d.up") {
      VStack(spacing: 0) {
        ForEach(entries) { entry in
          NavigationLink(value: entry.route) {
            BusinessEntryRow(entry: entry)
          }
          .buttonStyle(.plain)
          if entry.id != entries.last?.id {
            Divider().padding(.leading, 44)
          }
        }
      }
    }
  }

  private func makeEntries() -> [BusinessEntry] {
    let business = model.business
    var entries: [BusinessEntry] = [
      BusinessEntry(
        route: .invoices(.all), title: "Invoices", symbol: "doc.text", tint: .blue,
        count: business.invoices.count),
      BusinessEntry(
        route: .clients, title: "Clients", symbol: "person.2", tint: .teal,
        count: business.clients.filter { !$0.archived }.count),
    ]
    if business.role.seesPeople {
      entries.append(
        BusinessEntry(
          route: .people, title: "People", symbol: "person.text.rectangle", tint: .purple,
          count: business.employees.filter(\.isActive).count))
    }
    entries.append(
      BusinessEntry(
        route: .expiries, title: "Expiries", symbol: "calendar.badge.clock", tint: .orange,
        count: BusinessUI.visibleExpiries(in: business).count))
    let updates = TeamUpdatesView.visibleUpdates(in: business)
    if !updates.isEmpty {
      entries.append(
        BusinessEntry(
          route: .updates, title: "Team updates", symbol: "bell.badge", tint: .indigo,
          count: updates.count))
    }
    return entries
  }
}

private struct BusinessEntryRow: View {
  let entry: BusinessEntry

  var body: some View {
    HStack(spacing: 12) {
      Image(systemName: entry.symbol)
        .font(.body.weight(.semibold))
        .foregroundStyle(entry.tint)
        .frame(width: 32, height: 32)
        .background(entry.tint.opacity(0.15), in: .rect(cornerRadius: 9, style: .continuous))
        .accessibilityHidden(true)
      Text(entry.title)
        .font(.body.weight(.medium))
        .foregroundStyle(.primary)
      Spacer(minLength: 8)
      Text(entry.count, format: .number)
        .font(.subheadline)
        .foregroundStyle(.secondary)
        .monospacedDigit()
      Image(systemName: "chevron.forward")
        .font(.footnote.weight(.semibold))
        .foregroundStyle(.tertiary)
        .accessibilityHidden(true)
    }
    .padding(.vertical, 8)
    .contentShape(.rect)
    .accessibilityElement(children: .combine)
  }
}
