import MahamKit
import SwiftUI

// `/vat` and `/vat/:start` (src/apps/books/pages/accounting/vat.tsx), read
// only: the return periods with their status, and a return's boxes, each
// opening the transactions behind it.

@MainActor
enum AcVatData {
  static func settings(_ one: OneData) -> AcVatSettings {
    AcVatSettings(company: one.company, settings: one.acBooks.settings)
  }

  /// The filed return of a period.
  static func filed(_ one: OneData, start: String) -> JSONValue? {
    one.records(.vatReturns).first { $0.str("periodStart") == start }
  }
}

/// "VAT returns are off" (`NotRegistered`).
struct AcVatOff: View {
  @Environment(ShellRouter.self) private var router

  var body: some View {
    WebPage {
      PageHeader(t("VAT returns"))
      Card {
        WebEmptyState(
          icon: .landmark, title: t("VAT returns are off"),
          description: t("If your business is registered for VAT, turn returns on and choose how often you file.")
        ) {
          WebButton(t("Set up VAT returns")) { router.push(.settings(section: "accounting")) }
        }
      }
    }
  }
}

/// `/vat`: every return period from the first transaction to now.
struct AcVatPage: View {
  @Environment(AppModel.self) private var model
  @Environment(ShellRouter.self) private var router
  @Environment(\.palette) private var palette

  var body: some View {
    let one = model.one
    let settings = AcVatData.settings(one)
    if settings.registered {
      list(settings)
    } else {
      AcVatOff()
    }
  }

  private struct Row: Identifiable {
    let period: AcRange
    let record: JSONValue?
    let net: Int
    let status: String
    let due: String
    var id: String { period.from }
  }

  private func periodRows(_ settings: AcVatSettings) -> [Row] {
    let one = model.one
    let books = one.acBooks
    let now = AcDate.today
    let first = books.lines.reduce(now) { $1.date < $0 ? $1.date : $0 }
    var filed: [String: JSONValue] = [:]
    for record in one.records(.vatReturns) { filed[record.str("periodStart")] = record }
    var out: [Row] = []
    for period in AcVat.periods(settings, first, now) {
      let record = filed[period.from]
      let net =
        record.map { Int($0.num("net")) }
        ?? AcVat.compute(
          books.lines, period, settings.format, roles: books.roles, precision: books.precision,
          emirate: settings.emirate
        ).net
      out.append(
        Row(
          period: period, record: record, net: net,
          status: AcVat.status(period, filed: record != nil, format: settings.format, now: now),
          due: AcVat.dueDate(period, settings.format)))
    }
    return out.reversed()
  }

  @ViewBuilder
  private func list(_ settings: AcVatSettings) -> some View {
    let one = model.one
    let format = one.format
    let rows = periodRows(settings)
    let next = rows.last { $0.status == "ready" || $0.status == "overdue" }
    let arabic = LanguageStore.shared.isArabic
    WebPage(spacing: 16, refresh: { [model] in await model.one.sync() }) {
      PageHeader(t("VAT returns"), description: t("Worked out from your invoices, bills and expenses.")) {
        WebButton(t("VAT settings"), variant: .outline) { router.push(.settings(section: "accounting")) }
      }
      .padding(.bottom, -16)
      AcNotice(t(AcVat.office(settings.format)), tone: .blue)
      if let next {
        Card {
          CardBody {
            VStack(alignment: .leading, spacing: 4) {
              Text(t("Next return to file")).font(.web(14)).foregroundStyle(palette.slate(500))
              Text(nextTitle(next, format: format, arabic: arabic))
                .font(.web(18, .semibold))
                .foregroundStyle(palette.slate(900))
              Text(t("Due {date}", ["date": format.date(next.due)]))
                .font(.web(14, next.status == "overdue" ? .medium : .regular))
                .foregroundStyle(next.status == "overdue" ? palette[.red(600)] : palette.slate(500))
            }
            WebButton(t("Review return")) { router.push(.vatReturn(start: next.period.from)) }
          }
        }
      }
      ListCard {
        ForEach(rows) { row in
          periodRow(row, format: format, arabic: arabic)
        }
      }
    }
  }

  private func nextTitle(_ row: Row, format: CompanyFormat, arabic: Bool) -> String {
    let name = AcDate.periodName(row.period.from, row.period.to, arabic: arabic)
    let amount =
      row.net >= 0
      ? t("{amount} to pay", ["amount": format.acMoney(row.net)])
      : t("{amount} to reclaim", ["amount": format.acMoney(-row.net)])
    return "\(name) · \(amount)"
  }

  private func periodRow(_ row: Row, format: CompanyFormat, arabic: Bool) -> some View {
    AcTapRow(action: { router.push(.vatReturn(start: row.period.from)) }) {
      HStack(spacing: 12) {
        VStack(alignment: .leading, spacing: 3) {
          Text(AcDate.periodName(row.period.from, row.period.to, arabic: arabic))
            .font(.web(16, .medium))
            .foregroundStyle(palette.slate(900))
          Text(t("Due {date}", ["date": format.date(row.due)]))
            .font(.web(12, row.status == "overdue" ? .medium : .regular))
            .foregroundStyle(row.status == "overdue" ? palette[.red(600)] : palette.slate(500))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        VStack(alignment: .trailing, spacing: 4) {
          Text(format.acMoney(abs(row.net)))
            .font(.web(14, .semibold, tabular: true))
            .foregroundStyle(palette.slate(900))
            .environment(\.layoutDirection, .leftToRight)
          Text(row.net >= 0 ? t("to pay") : t("to reclaim")).font(.web(12)).foregroundStyle(palette.slate(500))
          Badge(status: AcVat.statusMeta(row.status))
        }
      }
      .padding(.horizontal, 16)
      .padding(.vertical, 12)
      .frame(minHeight: 56)
    }
  }
}

/// `/vat/:start`: one return, its boxes and the transactions behind each.
struct AcVatReturnPage: View {
  let start: String
  @Environment(AppModel.self) private var model
  @Environment(ShellRouter.self) private var router
  @Environment(\.palette) private var palette
  @Environment(SuiteState.self) private var suite: SuiteState?
  @State private var open: Set<String> = []
  @State private var filing = false
  @State private var paying: JSONValue?
  @State private var confirm: AwConfirm?

  init(start: String) {
    self.start = start
  }

  var body: some View {
    let one = model.one
    let settings = AcVatData.settings(one)
    if settings.registered {
      detail(settings)
    } else {
      AcVatOff()
    }
  }

  /// The boxes shown: as filed, or as the books are now.
  private func boxes(_ live: AcVatReturn, record: JSONValue?) -> [AcVatBox] {
    guard let record else { return live.boxes }
    return record.list("boxes").map { box in
      let id = box.str("id")
      let current = live.boxes.first { $0.id == id }
      return AcVatBox(
        id: id, label: box.str("label"), amount: Int(box.num("amount")), vat: box.number("vat").map { Int($0) },
        total: current?.total ?? false, whole: current?.whole ?? false)
    }
  }

  private func changed(_ live: AcVatReturn, record: JSONValue?) -> [String] {
    guard let record else { return [] }
    let filed = record.list("boxes")
    return live.boxes.filter { box in
      guard let was = filed.first(where: { $0.str("id") == box.id }) else { return true }
      return Int(was.num("amount")) != box.amount || Int(was.number("vat") ?? 0) != (box.vat ?? 0)
    }.map(\.id)
  }

  private func subtitle(_ period: AcRange, due: String, record: JSONValue?, format: CompanyFormat) -> String {
    var parts = ["\(format.date(period.from)) – \(format.date(period.to))", t("Due {date}", ["date": format.date(due)])]
    if let record {
      let reference = record.str("reference")
      parts.append(
        reference.isEmpty
          ? t("Filed {date}", ["date": format.date(record.text("filedOn"))])
          : t("Filed {date}, ref. {reference}", ["date": format.date(record.text("filedOn")), "reference": reference]))
    }
    return parts.joined(separator: " · ")
  }

  @ViewBuilder
  private func detail(_ settings: AcVatSettings) -> some View {
    let one = model.one
    let books = one.acBooks
    let format = one.format
    let period = AcVat.periodOf(start, settings)
    let live = AcVat.compute(
      books.lines, period, settings.format, roles: books.roles, precision: books.precision, emirate: settings.emirate)
    let record = AcVatData.filed(one, start: period.from)
    let now = AcDate.today
    let status = AcVat.status(period, filed: record != nil, format: settings.format, now: now)
    let due = AcVat.dueDate(period, settings.format)
    let shown = boxes(live, record: record)
    let changedBoxes = changed(live, record: record)
    let net = record.map { Int($0.num("net")) } ?? live.net
    let problems = books.problems.filter { problem in
      books.lines.contains { $0.sourceId == problem.sourceId && $0.date >= period.from && $0.date <= period.to }
    }
    let untaxed = uniqueSources(live.untaxed)
    let name = AcDate.periodName(period.from, period.to, arabic: LanguageStore.shared.isArabic)
    WebPage(spacing: 16, refresh: { [model] in await model.one.sync() }) {
      PageHeader(
        t("VAT return · {period}", ["period": name]),
        description: subtitle(period, due: due, record: record, format: format), breadcrumb: t("VAT returns"),
        onBreadcrumb: { router.back() }
      ) {
        Badge(status: AcVat.statusMeta(status))
        if writable {
          writeActions(record, net: net, period: period, now: now, format: format)
        }
      }
      .padding(.bottom, -16)
      if !changedBoxes.isEmpty {
        AcNotice(
          tp(
            changedBoxes.count,
            "The books changed after this return was filed (box {boxes}). Correct the difference in your next return or with the tax office.",
            "The books changed after this return was filed (boxes {boxes}). Correct the difference in your next return or with the tax office.",
            ["boxes": changedBoxes.joined(separator: ", ")]),
          icon: .triangleAlert)
      }
      if !untaxed.isEmpty {
        AcNotice(
          t(
            "Lines without a tax rate in {documents}. Choose a rate (zero-rated, exempt…) so they are reported correctly.",
            ["documents": untaxed.map(\.number).joined(separator: LanguageStore.shared.isArabic ? "، " : ", ")]),
          icon: .triangleAlert)
      }
      if !problems.isEmpty {
        AcNotice(problems.map { "\($0.number): \($0.text)" }.joined(separator: " "), icon: .triangleAlert)
      }
      ListCard {
        ForEach(shown.indices, id: \.self) { index in
          boxRow(shown[index], settings: settings, period: period, format: format)
        }
      }
      Card {
        CardBody {
          VStack(alignment: .leading, spacing: 4) {
            Text(net >= 0 ? t("VAT to pay") : t("VAT to reclaim")).font(.web(14)).foregroundStyle(palette.slate(500))
            Text(format.acMoney(abs(net)))
              .font(.web(24, .semibold, tabular: true))
              .foregroundStyle(palette.slate(900))
              .environment(\.layoutDirection, .leftToRight)
          }
          Text(netText(net, record: record, settings: settings, format: format))
            .font(.web(14))
            .foregroundStyle(palette.slate(500))
        }
      }
    }
    .awVatFileDialog($filing, period: period, figures: filingFigures(live, books: books, period: period))
    .awVatPaymentDialog($paying)
    .awConfirm($confirm)
  }

  /// Filing, paying and undoing a return change the books: owners, admins and accountants.
  private var writable: Bool {
    AwWrite.vat && AwAccess(model, suite).accounting
  }

  /// What filing keeps and posts, worked out only where it can be filed.
  private func filingFigures(_ live: AcVatReturn, books: AcBooks, period: AcRange) -> AwVatFigures {
    guard writable else { return AwVatFigures(boxes: [], net: 0, output: 0, input: 0) }
    return AwVatFiling.figures(live, books: books, period: period)
  }

  /// The payment (or refund) recorded for a filed return.
  private func paid(_ record: JSONValue) -> Bool {
    guard let id = record.text("paymentJournalId") else { return false }
    return model.one.record(.journals, id) != nil
  }

  /// Undo filing and Record payment (or refund) once filed; Mark as filed once the period is over.
  @ViewBuilder
  private func writeActions(
    _ record: JSONValue?, net: Int, period: AcRange, now: String, format: CompanyFormat
  ) -> some View {
    if let record {
      WebButton(t("Undo filing"), icon: .undo2, variant: .outline) {
        confirm = AwVatFiling.undo(record, model: model)
      }
      if net != 0 && !paid(record) {
        WebButton(net > 0 ? t("Record payment") : t("Record refund")) { paying = record }
      }
    } else {
      WebButton(t("Mark as filed")) { filing = true }
        .disabled(period.to >= now)
      if period.to >= now {
        Text(t("You can file after {date}.", ["date": format.date(period.to)]))
          .font(.web(12))
          .foregroundStyle(palette.slate(500))
      }
    }
  }

  private func uniqueSources(_ lines: [AcLine]) -> [AcLine] {
    var seen = Set<String>()
    var out: [AcLine] = []
    for line in lines where !seen.contains(line.sourceId) {
      seen.insert(line.sourceId)
      out.append(line)
    }
    return out
  }

  private func netText(_ net: Int, record: JSONValue?, settings: AcVatSettings, format: CompanyFormat) -> String {
    guard let record else { return t(AcVat.office(settings.format)) }
    if let id = record.text("paymentJournalId"), let payment = model.one.record(.journals, id) {
      return net >= 0
        ? t("Paid on {date}.", ["date": format.date(payment.text("date"))])
        : t("Received on {date}.", ["date": format.date(payment.text("date"))])
    }
    return net >= 0
      ? t("Recorded in your VAT liability account until paid.")
      : t("Recorded in your VAT liability account until refunded.")
  }

  @ViewBuilder
  private func boxRow(_ box: AcVatBox, settings: AcVatSettings, period: AcRange, format: CompanyFormat) -> some View {
    let expandable = !box.total
    let isOpen = open.contains(box.id)
    let action: (() -> Void)? = expandable ? { toggle(box.id) } : nil
    AcTapRow(action: action) {
      HStack(alignment: .top, spacing: 10) {
        HStack(spacing: 2) {
          if expandable {
            IconView(isOpen ? .chevronDown : .chevronRight, size: 14)
          }
          Text(box.id)
        }
        .font(.web(14))
        .foregroundStyle(palette.slate(500))
        .frame(width: 44, alignment: .leading)
        Text(t(box.label))
          .font(.web(14, box.total ? .semibold : .regular))
          .foregroundStyle(palette.slate(800))
          .frame(maxWidth: .infinity, alignment: .leading)
        VStack(alignment: .trailing, spacing: 2) {
          Text(box.whole ? format.acWhole(box.amount) : format.acMoney(box.amount))
            .font(.web(14, box.total ? .semibold : .regular, tabular: true))
            .foregroundStyle(palette.slate(900))
          if let vat = box.vat {
            Text(t("VAT {amount}", ["amount": format.acMoney(vat)]))
              .font(.web(12, tabular: true))
              .foregroundStyle(palette.slate(500))
          }
        }
        .environment(\.layoutDirection, .leftToRight)
      }
      .padding(.horizontal, 16)
      .padding(.vertical, 12)
      .background(box.total ? palette.slate(50).opacity(0.6) : Color.clear)
    }
    if isOpen {
      AcVatBoxLines(
        lines: AcVat.boxLines(
          model.one.acBooks.lines, period, settings.format, roles: model.one.acBooks.roles, emirate: settings.emirate,
          box: box.id), format: format)
    }
  }

  private func toggle(_ id: String) {
    if open.contains(id) { open.remove(id) } else { open.insert(id) }
  }
}

/// The transactions behind one box (`BoxLines`).
struct AcVatBoxLines: View {
  let lines: [(line: AcLine, amount: Int, vat: Int)]
  let format: CompanyFormat
  @Environment(AppModel.self) private var model
  @Environment(ShellRouter.self) private var router
  @Environment(\.palette) private var palette

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      if lines.isEmpty {
        Text(t("Nothing in this box.")).font(.web(14)).foregroundStyle(palette.slate(500)).padding(.vertical, 8)
      } else {
        ForEach(lines.indices, id: \.self) { index in
          lineRow(lines[index].line, amount: lines[index].amount, vat: lines[index].vat)
        }
      }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .padding(.horizontal, 16)
    .padding(.vertical, 8)
    .background(palette.slate(50).opacity(0.5))
  }

  private func lineRow(_ line: AcLine, amount: Int, vat: Int) -> some View {
    let contact = model.one.contactName(line.contactId)
    return Button {
      Haptics.play(.tap)
      router.push(AcLinks.source(line.source, line.sourceId, one: model.one))
    } label: {
      HStack(alignment: .top, spacing: 10) {
        VStack(alignment: .leading, spacing: 2) {
          Text("\(t(line.source.label)) \(line.number)").font(.web(12, .medium)).foregroundStyle(palette.primary(700))
          Text(line.text).font(.web(12)).foregroundStyle(palette.slate(500))
          Text([format.date(line.date), contact.isEmpty ? "—" : contact].joined(separator: " · "))
            .font(.web(12))
            .foregroundStyle(palette.slate(600))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        VStack(alignment: .trailing, spacing: 2) {
          Text(format.acMoney(amount)).font(.web(12, tabular: true)).foregroundStyle(palette.slate(800))
          if vat != 0 {
            Text(format.acMoney(vat)).font(.web(12, tabular: true)).foregroundStyle(palette.slate(800))
          }
        }
        .environment(\.layoutDirection, .leftToRight)
      }
      .padding(.vertical, 6)
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .overlay(alignment: .top) { Rectangle().fill(palette.slate(100)).frame(height: 1) }
  }
}
