import MahamKit
import SwiftUI

// Recurring invoices (`src/apps/books/pages/recurring/list.tsx`; the web's
// `/recurring/:id` is its editor, shown here to read): a schedule and an
// invoice template that a new invoice is made from each time.

/// A template's totals, worked out as the web's `calculate`
/// (`src/lib/calc.ts`) does: line amounts less their discounts, the
/// document discount, taxes grouped and rounded once per tax, charges, and
/// prices that may include tax.
struct CtTotals {
  var subtotal: Double = 0
  var discount: Double = 0
  var chargesTotal: Double = 0
  var taxTotal: Double = 0
  var total: Double = 0
}

enum CtTemplateCalc {
  private struct Bucket {
    var reverse: Bool
    var amount: Decimal
  }

  /// The totals of a recurring profile's template (no deposit, no retention).
  static func totals(_ template: JSONValue, taxExempt: Bool) -> CtTotals {
    let currency = template.text("currency") ?? "KWD"
    let places = max(0, min(6, Money.precision(currency)))
    let inclusive = template.flag("pricesIncludeTax")
    let docTaxes = taxExempt ? [] : valid(template.list("taxes"))
    var buckets: [String: Bucket] = [:]

    // Splits an amount into its taxes (inclusive prices back the net out first).
    func apply(_ amount: Decimal, _ taxes: [JSONValue]) {
      guard !taxes.isEmpty else { return }
      let charged = taxes.filter { !isReverse($0) }
      let rateSum = charged.reduce(Decimal(0)) { $0 + Money.dec($1.num("rate")) }
      let base = inclusive ? amount / (rateSum / 100 + 1) : amount
      for tax in taxes {
        let taxAmount = base * Money.dec(tax.num("rate")) / 100
        let key = taxKey(tax)
        var bucket = buckets[key] ?? Bucket(reverse: isReverse(tax), amount: 0)
        bucket.amount += taxAmount
        buckets[key] = bucket
      }
    }

    // 1. Line amounts.
    let items = template.list("items")
    var nets: [Decimal] = []
    for item in items {
      if item.str("kind") == "heading" {
        nets.append(0)
        continue
      }
      let gross = Money.dec(item.num("quantity")) * Money.dec(item.num("unitPrice"))
      let value = Money.dec(item.num("discount"))
      let off = item.str("discountType") == "amount" ? value : gross * value / 100
      nets.append(Money.round(gross - off, places))
    }
    let subtotal = nets.reduce(Decimal(0), +)

    // 2. The document discount.
    let docValue = Money.dec(template.num("discount"))
    let docOff = template.str("discountType") == "amount" ? docValue : subtotal * docValue / 100
    let discount = Money.round(docOff, places)
    let ratio: Decimal = subtotal.isZero ? 1 : (subtotal - discount) / subtotal

    // 3. Taxes on lines (their own and the document's).
    for (index, item) in items.enumerated() where item.str("kind") != "heading" {
      let own = taxExempt ? [] : valid(item.list("taxes"))
      apply(nets[index] * ratio, own + docTaxes)
    }

    // 4. Charges.
    var charges = Decimal(0)
    for charge in template.list("charges") {
      let amount = Money.round(Money.dec(charge.num("amount")), places)
      charges += amount
      apply(amount, taxExempt ? [] : valid(charge.list("taxes")))
    }

    // 5. Round once per tax, then total.
    var taxTotal = Decimal(0)
    for bucket in buckets.values where !bucket.reverse {
      taxTotal += Money.round(bucket.amount, places)
    }
    let afterDiscount = subtotal - discount + charges
    let total = inclusive ? afterDiscount : afterDiscount + taxTotal

    var result = CtTotals()
    result.subtotal = Money.toNumber(Money.round(subtotal, places))
    result.discount = Money.toNumber(discount)
    result.chargesTotal = Money.toNumber(Money.round(charges, places))
    result.taxTotal = Money.toNumber(Money.round(taxTotal, places))
    result.total = Money.toNumber(Money.round(total, places))
    return result
  }

  private static func isReverse(_ tax: JSONValue) -> Bool { tax.str("kind") == "reverse_charge" }

  /// Taxes with a name and a rate.
  private static func valid(_ taxes: [JSONValue]) -> [JSONValue] {
    taxes.filter { tax in
      let named = tax["name"]?.string.map { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty } ?? true
      return named && (tax.number("rate")?.isFinite ?? false)
    }
  }

  /// One group per tax name and rate; reverse charge apart.
  private static func taxKey(_ tax: JSONValue) -> String {
    let name = tax.str("name").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    let key = "\(name)|\(Money.jsString(tax.num("rate")))"
    return isReverse(tax) ? key + "|rc" : key
  }
}

/// The rules of a recurring profile as its pages show them.
@MainActor
enum CtRecurring {
  /// "Weekly", "Every 2 weeks", … (`FREQUENCY_LABEL`).
  static func frequencyLabel(_ frequency: String) -> String {
    switch frequency {
    case "weekly": t("Weekly")
    case "biweekly": t("Every 2 weeks")
    case "monthly": t("Monthly")
    case "bimonthly": t("Every 2 months")
    case "quarterly": t("Quarterly")
    case "semiannually": t("Every 6 months")
    case "yearly": t("Yearly")
    default: frequency
    }
  }

  /// Active (green), Paused (amber), Completed (slate).
  static func badge(_ status: String) -> Badge {
    switch status {
    case "paused": Badge(t("Paused"), tone: .amber)
    case "completed": Badge(t("Completed"), tone: .slate)
    default: Badge(t("Active"), tone: .green)
    }
  }

  /// Its name, else its client's, else "Recurring invoice".
  static func title(_ profile: JSONValue, one: OneData) -> String {
    if let name = profile.text("name") { return name }
    let client = one.contactName(profile.text("clientId"))
    return client.isEmpty ? t("Recurring invoice") : client
  }

  /// The template's total, as each invoice will be.
  static func total(_ profile: JSONValue, one: OneData) -> Double {
    let template = profile.obj("template") ?? .object([:])
    let exempt = one.record(.clients, profile.str("clientId"))?.flag("taxExempt") ?? false
    return CtTemplateCalc.totals(template, taxExempt: exempt).total
  }

  /// Why its next invoice was not created (`lockedOutBy`, `lockedOutText`):
  /// due in a period whose books are locked.
  static func lockText(_ profile: JSONValue, one: OneData) -> String? {
    let today = DocRules.today
    guard profile.str("status") == "active", let next = profile.text("nextIssueDate"), next <= today else {
      return nil
    }
    guard let lock = one.company?.obj("accounting")?.text("lockDate"), next <= lock else { return nil }
    let format = one.format
    return t(
      "The invoice due on {date} was not created: the books are locked up to {lock}. Change the lock date in Settings → Accounting, or the schedule.",
      ["date": format.date(next), "lock": format.date(lock)])
  }
}

// MARK: The list

/// `/recurring`: every profile, active first and soonest next, with its
/// client, schedule, total and next date.
struct CtRecurringListPage: View {
  @Environment(AppModel.self) private var model
  @Environment(ShellRouter.self) private var router

  var body: some View {
    let profiles = self.profiles
    WebPage(refresh: { [model] in await model.one.sync() }) {
      PageHeader(
        t("Recurring invoices"),
        description: t(
          "Invoices created automatically on a schedule — retainers, subscriptions, monthly services.")
      ) {
        WebButton(t("New recurring invoice"), icon: .plus, haptic: .press) { router.push(.newRecurring) }
      }
      if profiles.isEmpty {
        Card {
          if !model.one.hasData || isDownloading {
            DataLoadingRow()
          } else {
            WebEmptyState(
              icon: .`repeat`, title: t("No recurring invoices"),
              description: t("Set up an invoice once and it will be created for you every week, month or year.")
            ) {
              WebButton(t("New recurring invoice"), icon: .plus, haptic: .press) { router.push(.newRecurring) }
            }
          }
        }
      } else {
        ListCard {
          ForEach(profiles.map(Rec.init)) { record in
            CtRecurringRow(profile: record.raw)
          }
        }
      }
    }
  }

  private var isDownloading: Bool {
    if case .downloading = model.one.phase { return true }
    return false
  }

  /// Active, then paused, then completed; soonest next invoice first.
  private var profiles: [JSONValue] {
    let order = ["active": 0, "paused": 1, "completed": 2]
    return model.one.records(.recurring)
      .filter { !$0.flag("archived") }
      .sorted { a, b in
        let (oa, ob) = (order[a.str("status")] ?? 0, order[b.str("status")] ?? 0)
        if oa != ob { return oa < ob }
        return a.str("nextIssueDate") < b.str("nextIssueDate")
      }
  }
}

/// A profile in the list: its name and status; client · schedule · left ·
/// issued; a closed-period warning; the total and the next date.
struct CtRecurringRow: View {
  let profile: JSONValue
  @Environment(AppModel.self) private var model
  @Environment(ShellRouter.self) private var router

  var body: some View {
    let one = model.one
    let format = one.format
    let next = profile.text("nextIssueDate")
    CtListRow(
      title: CtRecurring.title(profile, one: one), subtitle: subtitle(one),
      detail: CtRecurring.lockText(profile, one: one), detailTone: .amber(700),
      amount: format.money(CtRecurring.total(profile, one: one), profile.obj("template")?.text("currency")),
      amountCaption: next.map { t("Next: {date}", ["date": format.date($0)]) } ?? t("Finished")
    ) {
      CtRecurring.badge(profile.str("status"))
    } action: {
      router.push(.recurringInvoice(id: profile.rid))
    }
  }

  private func subtitle(_ one: OneData) -> String {
    let client = one.contactName(profile.text("clientId"))
    var parts = [client.isEmpty ? t("No client") : client, CtRecurring.frequencyLabel(profile.str("frequency"))]
    if let left = profile.number("remainingCycles") {
      parts.append(tp(Int(left), "{count} left", "{count} left"))
    }
    parts.append(tp(Int(profile.num("issuedCount")), "{count} issued", "{count} issued"))
    return parts.joined(separator: " · ")
  }
}

// MARK: A profile

/// `/recurring/:id`: the schedule, the items, the totals, the notes and the
/// invoices made from it so far.
struct CtRecurringPage: View {
  let id: String
  @Environment(AppModel.self) private var model
  @Environment(ShellRouter.self) private var router

  var body: some View {
    let one = model.one
    let format = one.format
    let profile = one.record(.recurring, id)
    let clientId = profile?.text("clientId")
    let client = one.contactName(clientId)
    RecordDetailPage(
      record: profile, title: profile.map { CtRecurring.title($0, one: one) } ?? "",
      subtitle: client.isEmpty ? nil : client, breadcrumb: t("Recurring invoices")
    ) {
      if let profile { CtRecurring.badge(profile.str("status")) }
    } actions: {
      if let clientId, !client.isEmpty {
        WebButton(t("Open client"), icon: .userRound, variant: .outline, size: .sm) {
          router.push(.contact(.customer, id: clientId))
        }
      }
    } content: {
      if let profile {
        if let lock = CtRecurring.lockText(profile, one: one) {
          CtNote(.warning, lines: [lock])
        }
        CtInfoCard(t("Schedule"), description: scheduleLine(profile, format: format), rows: schedule(profile, format: format))
        let template = profile.obj("template") ?? .object([:])
        let currency = template.text("currency") ?? format.currency
        DocumentLinesCard(doc: template, type: .invoice, format: format, currency: currency)
        InfoCard(t("Totals"), rows: totals(profile, template: template, format: format, currency: currency))
        TextCard(title: t("PO / reference"), text: template.text("poNumber"))
        TextCard(title: t("Notes"), text: template.text("notes"))
        TextCard(title: t("Terms & conditions"), text: template.text("terms"))
        TextCard(title: t("Private notes"), text: template.text("privateNotes"))
        RelatedCard(t("Invoices"), records: invoices.map(Rec.init)) { record in
          DocumentRow(doc: record.raw, type: .invoice, format: format)
        }
      }
    }
  }

  /// "Monthly · Next invoice 01/12/2026".
  private func scheduleLine(_ profile: JSONValue, format: CompanyFormat) -> String {
    let next = format.date(profile.text("nextIssueDate"))
    return "\(CtRecurring.frequencyLabel(profile.str("frequency"))) · "
      + t("Next invoice {date}", ["date": next.isEmpty ? "—" : next])
  }

  private func schedule(_ profile: JSONValue, format: CompanyFormat) -> [CtRow] {
    let one = model.one
    let clientId = profile.str("clientId")
    var rows: [CtRow] = []
    rows.append(CtRow(t("Name"), profile.str("name")))
    rows.append(
      CtRow(
        t("Client"), one.contactName(clientId),
        route: clientId.isEmpty ? nil : .contact(.customer, id: clientId)))
    rows.append(CtRow(t("Frequency"), CtRecurring.frequencyLabel(profile.str("frequency"))))
    rows.append(CtRow(t("First invoice date"), format.date(profile.text("startDate"))))
    if let left = profile.number("remainingCycles") {
      rows.append(CtRow(t("Ends"), "\(t("After")) \(format.count(Int(left))) \(t("more invoices"))"))
    } else {
      rows.append(CtRow(t("Ends"), t("Never")))
    }
    let days = Int(profile.num("dueDays"))
    rows.append(CtRow(t("Payment due (days after issue)"), tp(days, "{count} day", "{count} days")))
    let template = profile.obj("template")
    let currency = template?.text("currency") ?? format.currency
    rows.append(CtRow(t("Currency"), currency))
    if currency != format.currency, let rate = template?.number("exchangeRate"), rate > 0 {
      rows.append(CtRow(t("Exchange rate"), format.quantity(rate), tabular: true))
    }
    rows.append(CtRow(t("Mark new invoices as sent"), profile.flag("markSent") ? t("Yes") : t("No")))
    rows.append(CtRow(t("Invoices"), tp(Int(profile.num("issuedCount")), "{count} issued", "{count} issued")))
    rows.append(CtRow(t("Last issued"), format.dateTime(profile.text("lastIssuedAt"))))
    return rows
  }

  private func totals(
    _ profile: JSONValue, template: JSONValue, format: CompanyFormat, currency: String
  ) -> [InfoRow] {
    let exempt = model.one.record(.clients, profile.str("clientId"))?.flag("taxExempt") ?? false
    let sums = CtTemplateCalc.totals(template, taxExempt: exempt)
    let money = { (value: Double) in format.money(value, currency) }
    var rows: [InfoRow] = []
    rows.append(InfoRow(t("Subtotal"), money(sums.subtotal), tabular: true))
    if sums.discount != 0 { rows.append(InfoRow(t("Discount"), money(-sums.discount), tabular: true)) }
    if sums.chargesTotal != 0 { rows.append(InfoRow(t("Charges"), money(sums.chargesTotal), tabular: true)) }
    if sums.taxTotal != 0 { rows.append(InfoRow(t("Tax"), money(sums.taxTotal), tabular: true)) }
    rows.append(InfoRow(t("Total"), money(sums.total), strong: true, tabular: true))
    return rows
  }

  /// The invoices made from this profile, newest first.
  private var invoices: [JSONValue] {
    model.one.records(.documents)
      .filter { $0.str("recurringId") == id && $0.str("type") == "invoice" }
      .sorted(by: DocRules.newestFirst)
  }
}
