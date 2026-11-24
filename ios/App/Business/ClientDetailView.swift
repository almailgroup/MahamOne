import MahamKit
import SwiftUI

/// One client: how to reach them, who to ask for, what they owe and their
/// invoices. Changes are made on mahamone.com.
struct ClientDetailView: View {
  @Environment(AppModel.self) private var model
  @State private var addingContact = false
  let client: Client

  init(client: Client) {
    self.client = client
  }

  var body: some View {
    let business = model.business
    // The newest copy, once the store has refreshed.
    let shown = business.client(client.id) ?? client
    let today = business.today
    let floor = LocalDate(year: 1, month: 1, day: 1)
    let invoices = business.invoices(for: shown.id)
      .sorted { ($0.issueDate ?? floor) > ($1.issueDate ?? floor) }
    let open = invoices.filter(\.isOpen)
    let overdue = open.filter { $0.isOverdue(today: today) }
    let actions = Self.actions(for: shown)
    let config = model.services?.config
    ScrollView {
      VStack(alignment: .leading, spacing: 16) {
        header(shown)
        if !actions.isEmpty {
          BusinessContactActions(actions: actions)
        }
        GlassEffectContainer(spacing: 12) {
          HStack(spacing: 12) {
            MetricTile(
              title: "Open balance", value: business.format(BusinessUI.openBalance(open)),
              symbol: "banknote", tint: .indigo, detail: String(localized: "\(open.count) open"))
            MetricTile(
              title: "Overdue", value: business.format(BusinessUI.openBalance(overdue)),
              symbol: "clock.badge.exclamationmark", tint: overdue.isEmpty ? .gray : .red,
              detail: String(localized: "\(overdue.count) invoices"))
          }
        }
        if !shown.contacts.isEmpty {
          contacts(shown)
        }
        invoicesSection(invoices)
        GlassEffectContainer(spacing: 10) {
          VStack(spacing: 10) {
            OpenInMahamOneButton(url: business.webURL(client: shown))
            Button {
              addingContact = true
            } label: {
              Label("Add to Contacts", systemImage: "person.crop.circle.badge.plus")
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.glass)
            .controlSize(.large)
          }
        }
      }
      .padding(.horizontal)
      .padding(.bottom, 32)
      .frame(maxWidth: 760)
      .frame(maxWidth: .infinity)
    }
    .mahamScreen()
    .navigationTitle(BusinessUI.name(shown))
    .navigationBarTitleDisplayMode(.inline)
    .refreshable { await business.refreshCompany() }
    .userActivity(ActivityType.client) { activity in
      activity.describe(client: shown, config: config)
    }
    .sheet(isPresented: $addingContact) {
      NewClientContactView(client: shown) {
        addingContact = false
      }
      .ignoresSafeArea()
    }
  }

  // MARK: Parts

  private func header(_ client: Client) -> some View {
    let name = BusinessUI.name(client)
    let other = BusinessUI.otherName(client.name, client.nameAr)
    return HStack(alignment: .top, spacing: 14) {
      AvatarView(initials: BusinessUI.initials(name), id: client.id, size: 56)
      VStack(alignment: .leading, spacing: 4) {
        Text(name)
          .font(.title2.bold())
          .lineLimit(3)
          .textSelection(.enabled)
        if let other {
          Text(other)
            .font(.headline)
            .foregroundStyle(.secondary)
            .textSelection(.enabled)
        }
        HStack(spacing: 10) {
          if !client.number.isEmpty {
            Text(client.number)
              .monospacedDigit()
          }
          if !client.city.isEmpty {
            Label(client.city, systemImage: "mappin.and.ellipse")
          }
        }
        .font(.subheadline)
        .foregroundStyle(.secondary)
        HStack(spacing: 6) {
          if client.isVendor {
            pill(client.isCustomer ? Text("Customer and vendor") : Text("Vendor"), tint: .purple)
          }
          if client.archived {
            pill(Text("Archived"), tint: .gray)
          }
        }
      }
      Spacer(minLength: 0)
    }
    .glassCard()
  }

  private func pill(_ text: Text, tint: Color) -> some View {
    text
      .font(.caption.weight(.semibold))
      .foregroundStyle(tint)
      .padding(.horizontal, 8)
      .padding(.vertical, 3)
      .background(tint.opacity(0.14), in: .capsule)
  }

  private func contacts(_ client: Client) -> some View {
    let people = client.contacts.sorted { $0.primary && !$1.primary }
    return GlassSection("Contacts", symbol: "person.crop.rectangle.stack") {
      VStack(spacing: 10) {
        ForEach(people) { contact in
          BusinessClientContactLine(contact: contact)
          if contact.id != people.last?.id {
            Divider()
          }
        }
      }
    }
  }

  private func invoicesSection(_ invoices: [SalesDocument]) -> some View {
    GlassSection("Invoices", symbol: "doc.text") {
      Text("\(invoices.count)")
        .foregroundStyle(.secondary)
        .monospacedDigit()
    } content: {
      if invoices.isEmpty {
        Text("No invoices yet.")
          .font(.subheadline)
          .foregroundStyle(.secondary)
      } else {
        LazyVStack(alignment: .leading, spacing: 8) {
          ForEach(invoices) { invoice in
            NavigationLink(value: invoice) {
              InvoiceRow(invoice: invoice, showsClient: false)
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            if invoice.id != invoices.last?.id {
              Divider()
            }
          }
        }
      }
    }
  }

  /// Call, Message, Email, FaceTime, the website and Maps, for what the
  /// client has.
  private static func actions(for client: Client) -> [BusinessContactAction] {
    var actions = BusinessContactActions.person(phone: client.bestPhone, email: client.bestEmail)
    if let url = BusinessUI.websiteURL(client.website) {
      actions.append(BusinessContactAction(id: "website", title: "Website", symbol: "safari.fill", url: url))
    }
    if let url = BusinessUI.mapsURL(client.city) {
      actions.append(BusinessContactAction(id: "maps", title: "Maps", symbol: "map.fill", url: url))
    }
    return actions
  }
}

/// Someone to ask for at a client, with a call and an email button.
private struct BusinessClientContactLine: View {
  let contact: ClientContact
  @Environment(\.openURL) private var openURL

  var body: some View {
    let name = contact.name.trimmingCharacters(in: .whitespaces)
    let phone = contact.phone.trimmingCharacters(in: .whitespaces)
    let email = contact.email.trimmingCharacters(in: .whitespaces)
    let call = BusinessUI.phoneURL("tel", phone)
    let mail = BusinessUI.emailURL(email)
    HStack(spacing: 10) {
      VStack(alignment: .leading, spacing: 2) {
        HStack(spacing: 6) {
          Group {
            if name.isEmpty {
              Text("Contact")
            } else {
              Text(name)
            }
          }
          .font(.body.weight(.medium))
          if contact.primary {
            Text("Main")
              .font(.caption2.weight(.semibold))
              .foregroundStyle(.tint)
              .padding(.horizontal, 6)
              .padding(.vertical, 2)
              .background(Color.accentColor.opacity(0.14), in: .capsule)
          }
        }
        if !phone.isEmpty {
          Text(phone)
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .textSelection(.enabled)
        }
        if !email.isEmpty {
          Text(email)
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .textSelection(.enabled)
        }
      }
      Spacer(minLength: 8)
      if let call {
        Button {
          openURL(call)
        } label: {
          Label("Call", systemImage: "phone.fill")
            .labelStyle(.iconOnly)
        }
        .buttonStyle(.glass)
        .buttonBorderShape(.circle)
        .accessibilityLabel(name.isEmpty ? Text("Call") : Text("Call \(name)"))
      }
      if let mail {
        Button {
          openURL(mail)
        } label: {
          Label("Email", systemImage: "envelope.fill")
            .labelStyle(.iconOnly)
        }
        .buttonStyle(.glass)
        .buttonBorderShape(.circle)
        .accessibilityLabel(name.isEmpty ? Text("Email") : Text("Email \(name)"))
      }
    }
  }
}
