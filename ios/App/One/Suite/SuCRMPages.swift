import MahamKit
import SwiftUI

// Maham CRM (`src/apps/crm`): the company's quotes as deals, from draft to
// won or lost, and the customers who haven't bought yet. Nothing of its own
// is stored: it reads the quotes, invoices and customers of Maham Books.

// MARK: The rules (src/apps/crm/lib/pipeline.ts)

/// Where a quote stands.
enum SuStage: String, CaseIterable, Sendable {
  case draft, open, won, lost

  init(status: String) {
    switch status {
    case "draft": self = .draft
    case "sent": self = .open
    case "accepted", "invoiced", "converted": self = .won
    default: self = .lost
    }
  }

  var label: String {
    switch self {
    case .draft: "Draft"
    case .open: "Waiting for an answer"
    case .won: "Won"
    case .lost: "Lost"
    }
  }

  var tone: Token {
    switch self {
    case .draft: .slate(400)
    case .open: .sky(500)
    case .won: .emerald(500)
    case .lost: .red(400)
    }
  }
}

/// A stage's quotes: how many, their value in the company's currency, and
/// those in another currency without a rate, left out of the value.
struct SuStageSummary: Identifiable {
  let stage: SuStage
  let count: Int
  let value: Double
  let foreign: Int
  var id: String { stage.rawValue }
}

/// A sent quote waiting for an answer for a week or more, or past its date.
struct SuFollowUp: Identifiable {
  let quote: JSONValue
  let days: Int
  let expired: Bool
  var id: String { quote.rid }
}

/// What a customer who hasn't bought yet is: quoted, quoted before, or not contacted.
enum SuProspectKind: String, Sendable {
  case quoted, contacted, new

  var order: Int {
    switch self {
    case .quoted: 0
    case .contacted: 1
    case .new: 2
    }
  }
}

struct SuProspect: Identifiable {
  let client: JSONValue
  let kind: SuProspectKind
  let openQuotes: Int
  let openValue: Double
  let foreign: Int
  var id: String { client.rid }
}

enum SuPipeline {
  /// A quote sent this many days ago without an answer is due a follow-up.
  static let followUpDays = 7
  /// Won and lost quotes of this many days count in the win rate.
  static let winRateDays = 365
  /// Quotes listed per stage before "And N more."
  static let perStage = 6

  static func stage(_ quote: JSONValue) -> SuStage { SuStage(status: quote.str("status")) }

  /// The quotes of the pipeline (not archived), newest first.
  static func quotes(_ documents: [JSONValue]) -> [JSONValue] {
    documents.filter { $0.str("type") == "quote" && !$0.flag("archived") }.sorted(by: newestFirst)
  }

  static func newestFirst(_ a: JSONValue, _ b: JSONValue) -> Bool {
    let (da, db) = (a.str("issueDate"), b.str("issueDate"))
    if da != db { return da > db }
    return a.str("number").localizedCompare(b.str("number")) == .orderedDescending
  }

  /// A quote's total in the company's currency, at its exchange rate; nil
  /// for one in another currency without a rate.
  static func baseValue(_ quote: JSONValue, base: String) -> Double? {
    let total = quote.obj("totals")?.num("total") ?? 0
    let currency = quote.text("currency") ?? base
    if currency == base { return total }
    guard let rate = quote.number("exchangeRate"), rate > 0 else { return nil }
    let value = Money.dec(total) * Money.dec(rate)
    return Money.toNumber(Money.round(value, Money.precision(base)))
  }

  static func sum(_ quotes: [JSONValue], base: String) -> Double {
    let values = quotes.compactMap { baseValue($0, base: base) }
    return Money.toNumber(Money.round(Money.sum(values), Money.precision(base)))
  }

  static func summaries(_ quotes: [JSONValue], base: String) -> [SuStageSummary] {
    SuStage.allCases.map { (stage: SuStage) -> SuStageSummary in
      let list = quotes.filter { self.stage($0) == stage }
      return SuStageSummary(
        stage: stage, count: list.count, value: sum(list, base: base),
        foreign: list.filter { baseValue($0, base: base) == nil }.count)
    }
  }

  /// Won out of won and lost in the last year, 0–100; nil before any is decided.
  static func winRate(_ quotes: [JSONValue], today: String) -> Double? {
    let since = ISODates.addDays(today, -winRateDays)
    let decided = quotes.filter { quote in
      let stage = self.stage(quote)
      return (stage == .won || stage == .lost) && String(quote.str("updatedAt").prefix(10)) >= since
    }
    guard !decided.isEmpty else { return nil }
    let won = decided.filter { stage($0) == .won }.count
    return (Double(won) / Double(decided.count) * 100).rounded()
  }

  /// The day a quote went out: when it was sent, else its date.
  static func sentOn(_ quote: JSONValue) -> String {
    SuDates.moment(quote.text("sentAt")).map { ISODates.string(from: $0) } ?? quote.str("issueDate")
  }

  /// Sent quotes waiting a week or more, or past their valid-until date: the oldest first.
  static func followUps(_ quotes: [JSONValue], today: String) -> [SuFollowUp] {
    let open = quotes.filter { stage($0) == .open }
    let all = open.map { quote in
      SuFollowUp(
        quote: quote, days: max(0, ISODates.daysBetween(sentOn(quote), today) ?? 0),
        expired: (quote.text("dueDate") ?? "9999") < today)
    }
    return all.filter { $0.expired || $0.days >= followUpDays }.sorted(by: followUpOrder)
  }

  static func followUpOrder(_ a: SuFollowUp, _ b: SuFollowUp) -> Bool {
    if a.days != b.days { return a.days > b.days }
    return a.quote.str("number").localizedCompare(b.quote.str("number")) == .orderedAscending
  }

  /// Customers who haven't bought yet: quoted ones first, then those quoted
  /// before, then the newest.
  static func prospects(clients: [JSONValue], documents: [JSONValue], base: String) -> [SuProspect] {
    var bought = Set<String>()
    var contacted = Set<String>()
    var quoted: [String: [JSONValue]] = [:]
    for doc in documents {
      let type = doc.str("type")
      let status = doc.str("status")
      let client = doc.str("clientId")
      if type == "invoice", status != "draft", status != "void" { bought.insert(client) }
      if type == "quote", status != "draft" { contacted.insert(client) }
      if type == "quote", !doc.flag("archived"), stage(doc) == .open { quoted[client, default: []].append(doc) }
    }
    let customers = clients.filter { client in
      client["isCustomer"]?.bool != false && !client.flag("archived") && !bought.contains(client.rid)
    }
    let list = customers.map { client in
      prospect(client, open: quoted[client.rid], contacted: contacted.contains(client.rid), base: base)
    }
    return list.sorted(by: prospectOrder)
  }

  static func prospect(_ client: JSONValue, open: [JSONValue]?, contacted: Bool, base: String) -> SuProspect {
    let kind: SuProspectKind = open != nil ? .quoted : contacted ? .contacted : .new
    let quotes = open ?? []
    return SuProspect(
      client: client, kind: kind, openQuotes: quotes.count, openValue: sum(quotes, base: base),
      foreign: quotes.filter { baseValue($0, base: base) == nil }.count)
  }

  static func prospectOrder(_ a: SuProspect, _ b: SuProspect) -> Bool {
    if a.kind != b.kind { return a.kind.order < b.kind.order }
    return a.client.str("createdAt") > b.client.str("createdAt")
  }

  /// "+ 2 in other currencies".
  static func foreignText(_ count: Int) -> String {
    tp(count, "+ {count} in another currency", "+ {count} in other currencies")
  }
}

// MARK: The pipeline

/// `/crm`: the key figures, the quotes to follow up, then each stage with its quotes.
struct SuPipelinePage: View {
  @Environment(AppModel.self) private var model
  @Environment(ShellRouter.self) private var router

  var body: some View {
    let one = model.one
    let format = one.format
    let today = DocRules.today
    let quotes = SuPipeline.quotes(one.records(.documents))
    let summaries = SuPipeline.summaries(quotes, base: format.currency)
    let followUps = SuPipeline.followUps(quotes, today: today)
    WebPage(spacing: 20, refresh: { [model] in await model.one.sync() }) {
      PageHeader(t("Pipeline"), description: t("Your quotes, from draft to won.")) {
        if !SuRole(model).readOnly {
          WebButton(t("New quote"), icon: .plus, haptic: .press) { router.push(.newSalesDocument(.quote)) }
        }
      }
      if suLoading(model, empty: quotes.isEmpty) {
        SuLoadingCard()
      } else {
        SuPipelineFigures(
          summaries: summaries, winRate: SuPipeline.winRate(quotes, today: today), followUps: followUps.count,
          format: format)
        if !followUps.isEmpty {
          SuFollowUpCard(followUps: followUps, format: format)
        }
        ForEach(summaries) { summary in
          SuStageColumn(
            summary: summary, quotes: quotes.filter { SuPipeline.stage($0) == summary.stage }, format: format)
        }
      }
    }
  }
}

/// Open quotes, Won, Win rate and To follow up, two to a row.
private struct SuPipelineFigures: View {
  let summaries: [SuStageSummary]
  let winRate: Double?
  let followUps: Int
  let format: CompanyFormat

  var body: some View {
    let columns = [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)]
    let open = summaries.first { $0.stage == .open }
    let won = summaries.first { $0.stage == .won }
    LazyVGrid(columns: columns, spacing: 12) {
      SuFigure(label: t("Open quotes"), value: format.money(open?.value ?? 0), hint: hint(open))
      SuFigure(label: t("Won"), value: format.money(won?.value ?? 0), hint: hint(won))
      SuFigure(label: t("Win rate"), value: winRate.map { format.percent($0) } ?? "—", hint: t("Last 12 months"))
      SuFigure(
        label: t("To follow up"), value: format.quantity(Double(followUps)),
        hint: tp(SuPipeline.followUpDays, "Sent {count} day ago or more", "Sent {count} days ago or more"))
    }
  }

  /// The count, and the quotes in other currencies the amount leaves out.
  private func hint(_ summary: SuStageSummary?) -> String {
    guard let summary else { return "" }
    let count = tp(summary.count, "{count} quote", "{count} quotes")
    return suJoin([count, summary.foreign > 0 ? SuPipeline.foreignText(summary.foreign) : nil])
  }
}

/// The quotes waiting longest for an answer (8 at most), each opening its page.
private struct SuFollowUpCard: View {
  let followUps: [SuFollowUp]
  let format: CompanyFormat
  @Environment(AppModel.self) private var model
  @Environment(ShellRouter.self) private var router
  @Environment(\.palette) private var palette

  var body: some View {
    Card {
      CardHeader(t("To follow up"))
      VStack(spacing: 0) {
        ForEach(followUps.prefix(8)) { item in
          SuRow(action: { router.push(.salesDocument(.quote, id: item.quote.rid)) }) {
            row(item)
          }
        }
      }
      .padding(.top, -1)
      .clipped()
    }
  }

  private func row(_ item: SuFollowUp) -> some View {
    let quote = item.quote
    let name = model.one.contactName(quote.text("clientId"))
    return HStack(alignment: .top, spacing: 10) {
      IconView(.clock, size: 16)
        .foregroundStyle(item.expired ? palette[.red(600)] : palette[.amber(600)])
        .padding(.top, 2)
      VStack(alignment: .leading, spacing: 2) {
        Text(suJoin([quote.text("number") ?? t("Draft"), name.isEmpty ? "—" : name]))
          .font(.web(14, .medium))
          .foregroundStyle(palette.slate(800))
          .lineLimit(1)
        Text(detail(item)).font(.web(12)).foregroundStyle(palette.slate(500))
      }
      .frame(maxWidth: .infinity, alignment: .leading)
      Text(format.money(quote.obj("totals")?.num("total") ?? 0, quote.text("currency")))
        .font(.web(14, .medium, tabular: true))
        .foregroundStyle(palette.slate(900))
        .environment(\.layoutDirection, .leftToRight)
    }
  }

  private func detail(_ item: SuFollowUp) -> String {
    if item.expired { return t("Expired on {date}", ["date": format.date(item.quote.text("dueDate"))]) }
    return tp(item.days, "Sent {count} day ago", "Sent {count} days ago")
  }
}

/// One stage: its dot, name and count, the value, and its first six quotes.
private struct SuStageColumn: View {
  let summary: SuStageSummary
  let quotes: [JSONValue]
  let format: CompanyFormat
  @Environment(ShellRouter.self) private var router
  @Environment(\.palette) private var palette

  var body: some View {
    let shape = RoundedRectangle(cornerRadius: WebRadius.lg, style: .continuous)
    VStack(alignment: .leading, spacing: 8) {
      HStack(spacing: 8) {
        Circle().fill(palette.color(summary.stage.tone)).frame(width: 8, height: 8)
        Text(t(summary.stage.label))
          .font(.web(14, .semibold))
          .foregroundStyle(palette.slate(800))
          .lineLimit(1)
          .frame(maxWidth: .infinity, alignment: .leading)
        Badge(format.count(summary.count))
      }
      .padding(.horizontal, 4)
      .accessibilityAddTraits(.isHeader)
      VStack(alignment: .leading, spacing: 0) {
        Text(format.money(summary.value)).environment(\.layoutDirection, .leftToRight)
        if summary.foreign > 0 {
          Text(SuPipeline.foreignText(summary.foreign))
        }
      }
      .font(.web(12))
      .foregroundStyle(palette.slate(500))
      .padding(.horizontal, 4)
      if quotes.isEmpty {
        Text(t("None"))
          .font(.web(12))
          .foregroundStyle(palette.slate(400))
          .frame(maxWidth: .infinity)
          .padding(.vertical, 16)
      } else {
        ForEach(quotes.prefix(SuPipeline.perStage).map(Rec.init)) { record in
          SuDealCard(quote: record.raw, format: format)
        }
      }
      if quotes.count > SuPipeline.perStage {
        SuLink(tp(quotes.count - SuPipeline.perStage, "And {count} more.", "And {count} more."), size: 12) {
          router.push(.salesDocuments(.quote))
        }
        .padding(.horizontal, 4)
      }
    }
    .padding(12)
    .background(palette.slate(50), in: shape)
    .ring(palette.hairline, in: shape)
  }
}

/// A quote in a stage: the customer, "number · date" and the total; opens the quote.
private struct SuDealCard: View {
  let quote: JSONValue
  let format: CompanyFormat
  @Environment(AppModel.self) private var model
  @Environment(ShellRouter.self) private var router
  @Environment(\.palette) private var palette

  var body: some View {
    let shape = RoundedRectangle(cornerRadius: WebRadius.md, style: .continuous)
    let name = model.one.contactName(quote.text("clientId"))
    Button {
      Haptics.play(.tap)
      router.push(.salesDocument(.quote, id: quote.rid))
    } label: {
      VStack(alignment: .leading, spacing: 2) {
        Text(name.isEmpty ? "—" : name)
          .font(.web(14, .medium))
          .foregroundStyle(palette.slate(900))
          .lineLimit(1)
        Text(suJoin([quote.text("number") ?? t("Draft"), format.date(quote.text("issueDate"))]))
          .font(.web(12))
          .foregroundStyle(palette.slate(500))
          .lineLimit(1)
        Text(format.money(quote.obj("totals")?.num("total") ?? 0, quote.text("currency")))
          .font(.web(14, .medium, tabular: true))
          .foregroundStyle(palette.slate(800))
          .environment(\.layoutDirection, .leftToRight)
          .padding(.top, 2)
      }
      .frame(maxWidth: .infinity, alignment: .leading)
      .padding(12)
      .background(palette.surface, in: shape)
      .ring(palette.hairline, in: shape)
      .boxShadow(WebShadow.xs, in: shape)
      .contentShape(shape)
    }
    .buttonStyle(PressedScale())
  }
}

// MARK: Prospects

/// `/crm/prospects`: customers who haven't bought yet, by how far along they are.
struct SuProspectsPage: View {
  @Environment(AppModel.self) private var model
  @Environment(ShellRouter.self) private var router
  @State private var view = "all"
  @State private var query = ""

  var body: some View {
    let one = model.one
    let list = SuPipeline.prospects(
      clients: one.records(.clients), documents: one.records(.documents), base: one.format.currency)
    WebPage(refresh: { [model] in await model.one.sync() }) {
      PageHeader(t("Prospects"), description: t("Customers who haven’t bought from you yet.")) {
        if !SuRole(model).readOnly {
          WebButton(t("New client"), icon: .plus, haptic: .press) { router.push(.newContact(.customer)) }
        }
      }
      if suLoading(model, empty: list.isEmpty) {
        SuLoadingCard()
      } else if list.isEmpty {
        Card {
          WebEmptyState(
            icon: .userRoundSearch, title: t("No prospects"),
            description: t("Every customer has been invoiced. New customers show here until their first invoice."))
        }
      } else {
        SuProspectList(list: list, view: $view, query: $query)
      }
    }
  }
}

private struct SuProspectList: View {
  let list: [SuProspect]
  @Binding var view: String
  @Binding var query: String
  @Environment(AppModel.self) private var model

  var body: some View {
    let shown = filtered
    let format = model.one.format
    ListCard {
      Segmented(selection: $view, options: options)
      TextInput(text: $query, placeholder: t("Search prospects…"), leadingIcon: .search)
    } rows: {
      if shown.isEmpty {
        SuNoMatch(t("No one matches your search"))
      } else {
        ForEach(shown) { prospect in
          SuProspectRow(prospect: prospect, format: format)
        }
      }
    }
  }

  private var options: [SegmentOption<String>] {
    [
      SegmentOption("all", t("All"), count: list.count),
      SegmentOption("quoted", t("Quoted"), count: count(.quoted)),
      SegmentOption("contacted", t("Quoted before"), count: count(.contacted)),
      SegmentOption("new", t("Not contacted"), count: count(.new)),
    ]
  }

  private func count(_ kind: SuProspectKind) -> Int {
    list.filter { $0.kind == kind }.count
  }

  private var filtered: [SuProspect] {
    list.filter { prospect in
      (view == "all" || prospect.kind.rawValue == view) && searchText(prospect).matches(query)
    }
  }

  private func searchText(_ prospect: SuProspect) -> String {
    let client = prospect.client
    return [client.str("name"), client.str("nameAr"), client.str("email"), client.str("phone")].joined(separator: " ")
  }
}

/// A prospect: the name, what was sent to them, and the open quotes' value (or "New").
private struct SuProspectRow: View {
  let prospect: SuProspect
  let format: CompanyFormat
  @Environment(ShellRouter.self) private var router
  @Environment(\.palette) private var palette

  var body: some View {
    let name = localName(prospect.client)
    ListRow(title: name.isEmpty ? "—" : name, subtitle: subtitle, amount: amount) {
      if prospect.kind == .quoted, prospect.foreign > 0 {
        Text(SuPipeline.foreignText(prospect.foreign)).font(.web(12)).foregroundStyle(palette.slate(500))
      }
      if prospect.kind == .new {
        Badge(t("New"), tone: .blue)
      }
    } action: {
      router.push(.contact(.customer, id: prospect.client.rid))
    }
  }

  private var subtitle: String {
    switch prospect.kind {
    case .quoted: tp(prospect.openQuotes, "{count} open quote", "{count} open quotes")
    case .contacted: t("No open quote")
    case .new: t("Added {date}", ["date": format.date(SuDates.localDay(prospect.client.text("createdAt")))])
    }
  }

  private var amount: String? {
    guard prospect.kind == .quoted, prospect.openQuotes > prospect.foreign else { return nil }
    return format.money(prospect.openValue)
  }
}
