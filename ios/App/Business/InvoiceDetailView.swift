import MahamKit
import SwiftUI

/// One invoice: who it is for, what it comes to, what is still owed and by
/// when, and its lines. Changes are made on mahamone.com.
struct InvoiceDetailView: View {
  @Environment(AppModel.self) private var model
  @Environment(\.openURL) private var openURL
  let invoice: SalesDocument

  init(invoice: SalesDocument) {
    self.invoice = invoice
  }

  var body: some View {
    let business = model.business
    // The newest copy, once the store has refreshed.
    let doc = business.invoice(invoice.id) ?? invoice
    let client = business.client(doc.clientId)
    let today = business.today
    let overdue = doc.isOverdue(today: today)
    let config = model.services?.config
    ScrollView {
      VStack(alignment: .leading, spacing: 16) {
        header(doc, client: client, overdue: overdue, business: business)
        actionButtons(doc, client: client, business: business)
        amounts(doc, overdue: overdue, business: business)
        if doc.issueDate != nil || doc.dueDate != nil || !doc.poNumber.isEmpty {
          dates(doc, overdue: overdue, today: today)
        }
        if !doc.items.isEmpty {
          lines(doc, business: business)
        }
        let notes = doc.notes.trimmingCharacters(in: .whitespacesAndNewlines)
        if !notes.isEmpty {
          GlassSection("Notes", symbol: "note.text") {
            Text(notes)
              .font(.subheadline)
              .frame(maxWidth: .infinity, alignment: .leading)
              .textSelection(.enabled)
          }
        }
      }
      .padding(.horizontal)
      .padding(.bottom, 32)
      .frame(maxWidth: 760)
      .frame(maxWidth: .infinity)
    }
    .mahamScreen()
    .navigationTitle(doc.number.isEmpty ? String(localized: "Invoice") : doc.number)
    .navigationBarTitleDisplayMode(.inline)
    .refreshable {
      await Haptics.refresh()
      await business.refreshCompany()
    }
    .userActivity(ActivityType.invoice) { activity in
      activity.describe(invoice: doc, config: config)
    }
  }

  // MARK: Parts

  private func header(_ doc: SalesDocument, client: Client?, overdue: Bool, business: BusinessStore) -> some View {
    VStack(alignment: .leading, spacing: 12) {
      HStack(alignment: .firstTextBaseline, spacing: 10) {
        Text(doc.number.isEmpty ? "—" : doc.number)
          .font(.title2.bold())
          .monospacedDigit()
          .textSelection(.enabled)
        Spacer(minLength: 8)
        DocumentBadge(status: doc.status, overdue: overdue)
      }
      if let client {
        NavigationLink(value: client) {
          HStack(spacing: 6) {
            Label(BusinessUI.name(client), systemImage: "building.2")
              .lineLimit(2)
            Image(systemName: "chevron.forward")
              .font(.caption.weight(.semibold))
              .foregroundStyle(.tertiary)
              .accessibilityHidden(true)
          }
          .font(.headline)
          .contentShape(.rect)
        }
        .buttonStyle(.plain)
      } else {
        Label("Unknown client", systemImage: "building.2")
          .font(.headline)
          .foregroundStyle(.secondary)
      }
      VStack(alignment: .leading, spacing: 2) {
        Text(BusinessUI.money(doc.totals.total, currency: doc.currency, in: business))
          .font(.largeTitle.bold())
          .monospacedDigit()
          .lineLimit(1)
          .minimumScaleFactor(0.5)
        if doc.isOpen {
          Text("Balance \(BusinessUI.money(doc.totals.balance, currency: doc.currency, in: business))")
            .font(.subheadline.weight(.medium))
            .foregroundStyle(overdue ? Color.red : Color.secondary)
        }
      }
    }
    .glassCard(tint: overdue ? Color.red : nil)
  }

  private func actionButtons(_ doc: SalesDocument, client: Client?, business: BusinessStore) -> some View {
    let web = business.webURL(invoice: doc)?.absoluteURL
    let phone: String? = client?.bestPhone
    let email: String? = client?.bestEmail
    let subject: String? = doc.number.isEmpty ? nil : String(localized: "Invoice \(doc.number)")
    let call: URL? = phone.flatMap { BusinessUI.phoneURL("tel", $0) }
    let mail: URL? = email.flatMap { BusinessUI.emailURL($0, subject: subject) }
    return GlassEffectContainer(spacing: 10) {
      VStack(spacing: 10) {
        OpenInMahamOneButton(url: web)
        if web != nil || call != nil || mail != nil {
          HStack(spacing: 10) {
            if let web {
              ShareLink(item: web) {
                BusinessActionLabel(title: "Share", symbol: "square.and.arrow.up")
              }
              .buttonStyle(.glass)
              .buttonBorderShape(.roundedRectangle(radius: 18))
            }
            if let call {
              Button {
                openURL(call)
              } label: {
                BusinessActionLabel(title: "Call", symbol: "phone.fill")
              }
              .buttonStyle(.glass)
              .buttonBorderShape(.roundedRectangle(radius: 18))
            }
            if let mail {
              Button {
                openURL(mail)
              } label: {
                BusinessActionLabel(title: "Email", symbol: "envelope.fill")
              }
              .buttonStyle(.glass)
              .buttonBorderShape(.roundedRectangle(radius: 18))
            }
          }
        }
      }
    }
  }

  private func amounts(_ doc: SalesDocument, overdue: Bool, business: BusinessStore) -> some View {
    let totals = doc.totals
    let currency = doc.currency
    return GlassSection("Amounts", symbol: "sum") {
      VStack(spacing: 8) {
        BusinessInfoRow(title: "Subtotal", value: BusinessUI.money(totals.subtotal, currency: currency, in: business))
        BusinessInfoRow(title: "Tax", value: BusinessUI.money(totals.taxTotal, currency: currency, in: business))
        Divider()
        BusinessInfoRow(
          title: "Total", value: BusinessUI.money(totals.total, currency: currency, in: business), emphasized: true)
        BusinessInfoRow(title: "Paid", value: BusinessUI.money(totals.paid, currency: currency, in: business))
        BusinessInfoRow(
          title: "Balance", value: BusinessUI.money(totals.balance, currency: currency, in: business),
          tint: overdue ? Color.red : nil, emphasized: true)
      }
    }
  }

  private func dates(_ doc: SalesDocument, overdue: Bool, today: LocalDate) -> some View {
    GlassSection("Dates", symbol: "calendar") {
      VStack(spacing: 8) {
        if let issued = doc.issueDate {
          BusinessInfoRow(title: "Issued", value: issued.display)
        }
        if let due = doc.dueDate {
          BusinessInfoRow(title: "Due", value: due.display, tint: overdue ? Color.red : nil)
        }
        if overdue {
          BusinessInfoRow(
            title: "Overdue by", value: String(localized: "\(doc.daysOverdue(today: today)) days"), tint: .red,
            emphasized: true)
        }
        if !doc.poNumber.isEmpty {
          BusinessInfoRow(title: "PO number", value: doc.poNumber)
        }
      }
    }
  }

  private func lines(_ doc: SalesDocument, business: BusinessStore) -> some View {
    let items = Array(doc.items.enumerated())
    let count = doc.items.filter { $0.kind != "heading" }.count
    return GlassSection("Lines", symbol: "list.bullet") {
      Text("\(count)")
        .foregroundStyle(.secondary)
        .monospacedDigit()
    } content: {
      VStack(alignment: .leading, spacing: 10) {
        ForEach(items, id: \.offset) { index, line in
          BusinessInvoiceLineRow(
            line: line,
            unitPrice: BusinessUI.money(line.unitPrice, currency: doc.currency, in: business),
            amount: BusinessUI.money(line.amount, currency: doc.currency, in: business))
          if index < items.count - 1 {
            Divider()
          }
        }
      }
    }
  }
}

/// One line of an invoice: what it is, how many at what price, and its
/// amount; or a heading between them.
private struct BusinessInvoiceLineRow: View {
  let line: DocumentLine
  let unitPrice: String
  let amount: String

  var body: some View {
    let name = line.name.trimmingCharacters(in: .whitespacesAndNewlines)
    let description = line.description.trimmingCharacters(in: .whitespacesAndNewlines)
    let title = name.isEmpty ? description : name
    let unit = line.unit.trimmingCharacters(in: .whitespaces)
    let quantity = line.quantity.formatted(.number.precision(.fractionLength(0...3)))
    if line.kind == "heading" {
      Text(title)
        .font(.subheadline.weight(.bold))
        .padding(.top, 4)
        .accessibilityAddTraits(.isHeader)
    } else {
      HStack(alignment: .firstTextBaseline, spacing: 12) {
        VStack(alignment: .leading, spacing: 3) {
          Text(title)
            .font(.subheadline.weight(.medium))
          if !name.isEmpty, !description.isEmpty, description != name {
            Text(description)
              .font(.caption)
              .foregroundStyle(.secondary)
          }
          Group {
            if unit.isEmpty {
              Text("\(quantity) × \(unitPrice)")
            } else {
              Text("\(quantity) \(unit) × \(unitPrice)")
            }
          }
          .font(.caption)
          .foregroundStyle(.secondary)
          .monospacedDigit()
        }
        Spacer(minLength: 8)
        Text(amount)
          .font(.subheadline.weight(.semibold))
          .monospacedDigit()
      }
      .accessibilityElement(children: .combine)
    }
  }
}
