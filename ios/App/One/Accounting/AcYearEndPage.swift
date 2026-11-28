import MahamKit
import SwiftUI

// `/year-end` (src/apps/books/pages/accounting/year-end.tsx): the profit for
// a financial year, the statutory reserve and the levies as the web proposes
// them (or as the year was closed with), closing the year with the amounts
// as typed and reopening it, and the closed years.

struct AcYearEndPage: View {
  @Environment(AppModel.self) private var model
  @Environment(ShellRouter.self) private var router
  @Environment(\.palette) private var palette
  @Environment(SuiteState.self) private var suite: SuiteState?
  @State private var chosen: String?
  /// The amounts typed over the proposals, by kind, in major units.
  @State private var amounts: [String: Double] = [:]
  @State private var lock = true
  @State private var busy = false
  @State private var confirm: AwConfirm?

  var body: some View {
    let one = model.one
    let books = one.acBooks
    let format = one.format
    let today = AcDate.today
    let closes = one.records(.yearEnds)
    let closedYears = Set(closes.filter { $0.str("status") == "closed" }.map { $0.str("yearEnd") })
    let years = AcFiscal.years(books.lines.first?.date, books.fiscalYearEnd, today)
    let year = selectedYear(years, closedYears: closedYears, today: today)
    let close = closes.first { $0.str("status") == "closed" && $0.str("yearEnd") == year.to }
    let profile = KuwaitRules.kuwaitProfile(one.company)
    let rates = AcLevyRates(books.settings.levies)
    let exclude = Set((close?.list("journalIds") ?? []).compactMap(\.string))
    let figures = AcYearEnd.figures(books, date: year.to, profile: profile, rates: rates, exclude: exclude)
    let applies = figures.proposals.filter(\.applies)
    let label = AcFiscal.label(year.from, year.to)
    WebPage(spacing: 16, refresh: { [model] in await model.one.sync() }) {
      PageHeader(
        t("Year-end close"),
        description: t(
          "Works out the statutory reserve and the levies on the profit for the year, posts them and locks the year."),
        breadcrumb: t("Reports"), onBreadcrumb: { router.push(.reports) }
      )
      .padding(.bottom, -16)
      AcPayrollNote()
      Card {
        CardBody {
          Field(t("Financial year")) {
            Select(selection: yearBinding(year), options: yearOptions(years, closedYears))
          }
          Text(verbatim: "\(format.date(year.from)) – \(format.date(year.to))")
            .font(.web(14))
            .foregroundStyle(palette.slate(500))
        }
      }
      if year.to >= today, close == nil {
        AcNotice(t("This year ends on {date}. Close it once its figures are final.", ["date": format.date(year.to)]))
      }
      if close == nil, depreciationMissing(year) {
        AcNotice(
          t(
            "Depreciation has not been run for {month} yet.",
            ["month": AcDate.monthLabel(AcDate.period(year.to), arabic: LanguageStore.shared.isArabic)]),
          icon: .triangleAlert, link: t("Run depreciation"), onLink: { router.push(.assets) })
      }
      profitCard(figures, applies: applies, close: close, label: label, rates: rates)
      if let close {
        closedCard(close, label: label, blocked: reopenBlocked(year, closes: closes, settings: books.settings))
      } else if writable {
        closeCard(year, figures: figures, applies: applies, label: label, laterClosed: laterClosed(year, closes))
      }
      companyCard(figures, profile: profile, applies: applies, close: close)
      closedYearsCard(closes)
    }
    .awConfirm($confirm)
  }

  /// Closing and reopening a year change the books: owners, admins and accountants.
  private var writable: Bool {
    AwWrite.yearEnd && AwAccess(model, suite).accounting
  }

  // MARK: Choosing the year

  private func selectedYear(_ years: [AcRange], closedYears: Set<String>, today: String) -> AcRange {
    if let chosen, let found = years.first(where: { $0.to == chosen }) { return found }
    if let open = years.first(where: { $0.to < today && !closedYears.contains($0.to) }) { return open }
    return years.first ?? AcRange(from: today, to: today)
  }

  private func yearBinding(_ year: AcRange) -> Binding<String> {
    Binding(
      get: { chosen ?? year.to },
      set: {
        chosen = $0
        amounts = [:]
      })
  }

  private func yearOptions(_ years: [AcRange], _ closed: Set<String>) -> [SelectOption<String>] {
    years.map { year in
      let label = AcFiscal.label(year.from, year.to)
      return SelectOption(year.to, closed.contains(year.to) ? "\(label) · \(t("Closed"))" : label)
    }
  }

  private func depreciationMissing(_ year: AcRange) -> Bool {
    let one = model.one
    let assets = one.records(.assets).filter { $0.str("status") == "active" }
    if assets.isEmpty { return false }
    let last = AcDate.period(year.to)
    return !AcAssets.activeRuns(one.records(.depreciationRuns)).contains { $0.str("period") >= last }
  }

  // MARK: Cards

  /// As the year was closed with, or as typed over the proposal (`amountOf`).
  private func amountOf(_ proposal: AcYearEndProposal, _ close: JSONValue?) -> Int {
    let p = model.one.acBooks.precision
    guard let close else { return AcLedger.minor(amounts[proposal.kind] ?? major(proposal.amount, p), p) }
    let line = close.list("lines").first { $0.str("kind") == proposal.kind }
    return AcLedger.minor(line?.num("amount") ?? 0, p)
  }

  private func major(_ minor: Int, _ p: Int) -> Double {
    Money.toNumber(Money.fromMinor(Int64(minor), p))
  }

  /// The amount of an open year's line, typed over the proposal.
  private func amountBinding(_ proposal: AcYearEndProposal) -> Binding<Double> {
    let kind = proposal.kind
    let proposed = major(proposal.amount, model.one.acBooks.precision)
    return Binding(get: { amounts[kind] ?? proposed }, set: { amounts[kind] = $0 })
  }

  @ViewBuilder
  private func profitCard(
    _ figures: AcYearEndFigures, applies: [AcYearEndProposal], close: JSONValue?, label: String, rates: AcLevyRates
  ) -> some View {
    let format = model.one.format
    let levies = applies.filter { $0.kind != "statutory_reserve" && $0.kind != "voluntary_reserve" }
    Card {
      CardHeader(t("Profit for {year}", ["year": label]), description: t("Before KFAS, Zakat, NLST and income tax.")) {
        Text(format.acMoney(figures.profitBeforeLevies))
          .font(.web(18, .semibold, tabular: true))
          .foregroundStyle(figures.profitBeforeLevies < 0 ? palette[.red(600)] : palette.slate(900))
          .environment(\.layoutDirection, .leftToRight)
      }
      VStack(alignment: .leading, spacing: 0) {
        if figures.profitBeforeLevies <= 0 {
          Text(
            t("There is no profit this year, so nothing is due. You can still close the year to lock it.")
          )
          .font(.web(14))
          .foregroundStyle(palette.slate(600))
          .padding(.vertical, 12)
        }
        ForEach(applies.indices, id: \.self) { index in
          proposalRow(
            applies[index], amount: amountOf(applies[index], close), figures: figures, rates: rates,
            editing: close == nil && writable)
        }
        if levies.isEmpty {
          Text(
            t(
              "KFAS and Zakat apply to shareholding companies, NLST to listed ones, and income tax to foreign-owned profits. None apply to this company."
            )
          )
          .font(.web(14))
          .foregroundStyle(palette.slate(500))
          .padding(.vertical, 12)
        }
        HStack(alignment: .top, spacing: 8) {
          IconView(.info, size: 14).padding(.top, 2)
          VStack(alignment: .leading, spacing: 4) {
            Text(t("Rates follow Kuwaiti law. Check the amounts with your auditor before posting."))
            Button {
              Haptics.play(.tap)
              router.push(.settings(section: "accounting"))
            } label: {
              Text(t("Change the rates")).underline()
            }
            .buttonStyle(.plain)
          }
        }
        .font(.web(12))
        .foregroundStyle(palette.slate(500))
        .padding(.vertical, 12)
      }
      .padding(.horizontal, 20)
      .padding(.bottom, 4)
    }
  }

  private func proposalRow(
    _ proposal: AcYearEndProposal, amount: Int, figures: AcYearEndFigures, rates: AcLevyRates, editing: Bool
  ) -> some View {
    let format = model.one.format
    return HStack(alignment: .center, spacing: 12) {
      VStack(alignment: .leading, spacing: 2) {
        Text(t(AcYearEnd.label(proposal.kind))).font(.web(14, .medium)).foregroundStyle(palette.slate(900))
        Text(explanation(proposal, figures: figures, rates: rates, format: format))
          .font(.web(12))
          .foregroundStyle(palette.slate(500))
      }
      .frame(maxWidth: .infinity, alignment: .leading)
      proposalAmount(proposal, amount: amount, editing: editing, format: format)
    }
    .padding(.vertical, 12)
    .overlay(alignment: .top) { Rectangle().fill(palette.slate(100)).frame(height: 1) }
  }

  /// Why each line is proposed, in plain words (`explanation`).
  private func explanation(
    _ p: AcYearEndProposal, figures: AcYearEndFigures, rates: AcLevyRates, format: CompanyFormat
  ) -> String {
    let rate = format.percent(p.rate)
    switch p.kind {
    case "statutory_reserve":
      guard let room = p.room else {
        return t(
          "{rate} of the profit. Enter the capital in the company profile to apply the limit.", ["rate": rate])
      }
      if room == 0 {
        return t(
          "The reserve has reached {cap} of the capital ({capital}), so no transfer is needed.",
          ["cap": format.percent(rates.statutoryReserveCap), "capital": format.acMoney(figures.capital)])
      }
      return t(
        "{rate} of the profit, until the reserve reaches {cap} of the capital. Room left: {room}.",
        ["rate": rate, "cap": format.percent(rates.statutoryReserveCap), "room": format.acMoney(room)])
    case "voluntary_reserve":
      return t("Optional, as decided by the partners or the general assembly.")
    case "kfas":
      return t("{rate} of the profit after the statutory reserve and losses brought forward.", ["rate": rate])
    case "zakat":
      return t("{rate} of the profit (Law 46/2006).", ["rate": rate])
    case "nlst":
      return t("{rate} of the profit of listed companies (Law 19/2000).", ["rate": rate])
    default:
      return t(
        "{rate} of the foreign-owned share of the profit ({base}).", ["rate": rate, "base": format.acMoney(p.base)])
    }
  }

  @ViewBuilder
  private func proposalAmount(_ proposal: AcYearEndProposal, amount: Int, editing: Bool, format: CompanyFormat)
    -> some View
  {
    if editing {
      AwAmountField(value: amountBinding(proposal), placeholder: t(AcYearEnd.label(proposal.kind)), blankZero: false)
        .frame(width: 150)
    } else {
      Text(format.acMoney(amount))
        .font(.web(14, .semibold, tabular: true))
        .foregroundStyle(palette.slate(900))
        .environment(\.layoutDirection, .leftToRight)
    }
  }

  // MARK: Closing and reopening

  /// `isolate`: a date kept whole inside Arabic text.
  private func isolate(_ text: String) -> String {
    LanguageStore.shared.isArabic && !text.isEmpty ? "\u{2068}\(text)\u{2069}" : text
  }

  private func laterClosed(_ year: AcRange, _ closes: [JSONValue]) -> Bool {
    closes.contains { $0.str("status") == "closed" && $0.str("yearEnd") > year.to }
  }

  /// Why the year can't be reopened yet: a later year is closed, or the lock date covers it.
  private func reopenBlocked(_ year: AcRange, closes: [JSONValue], settings: AcSettings) -> String? {
    if laterClosed(year, closes) { return t("Reopen the later years first.") }
    let lockDate = settings.lockDate ?? ""
    if !lockDate.isEmpty && lockDate >= year.to {
      return t("To reopen the year, remove the lock date in Settings → Accounting first.")
    }
    return nil
  }

  @ViewBuilder
  private func closedCard(_ close: JSONValue, label: String, blocked: String?) -> some View {
    let format = model.one.format
    Card {
      CardBody {
        HStack(spacing: 8) {
          IconView(.circleCheck, size: 16)
          Text(t("Closed on {date}", ["date": isolate(format.dateTime(close.text("createdAt")))]))
          if close.text("lockedTo") != nil { Badge(t("Locked")) }
        }
        .font(.web(14))
        .foregroundStyle(palette[.emerald(700)])
        if writable {
          WebButton(t("Reopen"), icon: .undo2, variant: .outline) { askReopen(close, label: label) }
            .disabled(blocked != nil)
        }
      }
      if writable, let blocked {
        Text(blocked)
          .font(.web(12))
          .foregroundStyle(palette.slate(500))
          .padding(.horizontal, 20)
          .padding(.bottom, 16)
          .padding(.top, -4)
      }
    }
  }

  /// "Lock the books up to {date}" and "Close {year}".
  private func closeCard(
    _ year: AcRange, figures: AcYearEndFigures, applies: [AcYearEndProposal], label: String, laterClosed: Bool
  ) -> some View {
    let format = model.one.format
    return Card {
      CardBody {
        Switch(
          t("Lock the books up to {date}", ["date": isolate(format.date(year.to))]),
          description: t("Nothing dated on or before it can be changed afterwards."), isOn: $lock)
        WebButton(t("Close {year}", ["year": label]), icon: .calendarCheck, loading: busy) {
          askClose(year, figures: figures, applies: applies, label: label)
        }
        .disabled(laterClosed)
      }
    }
  }

  /// "Close {year}?", then the levies and reserves posted on the last day of the year.
  private func askClose(_ year: AcRange, figures: AcYearEndFigures, applies: [AcYearEndProposal], label: String) {
    let date = isolate(model.one.format.date(year.to))
    let description =
      lock
      ? t("The entries are dated {date} and the books are locked up to that date.", ["date": date])
      : t("The entries are dated {date}.", ["date": date])
    confirm = AwConfirm(
      title: t("Close {year}?", ["year": label]), description: description, confirmLabel: t("Close the year")
    ) {
      closeYear(year, figures: figures, applies: applies, label: label)
    }
  }

  private func closeYear(_ year: AcRange, figures: AcYearEndFigures, applies: [AcYearEndProposal], label: String) {
    guard let companyId = model.one.companyId else { return }
    let p = model.one.acBooks.precision
    let lines = applies.map { proposal in
      AwYearEndLine(
        kind: proposal.kind, base: major(proposal.base, p), rate: proposal.rate,
        amount: major(amountOf(proposal, nil), p))
    }
    let profit = major(figures.profitBeforeLevies, p)
    let locking = lock
    busy = true
    Task {
      let closed = await AwSave.perform(model, done: t("Financial year {year} closed", ["year": label])) { ctx, tr in
        try AwYearEnd.close(
          ctx, companyId: companyId, yearStart: year.from, yearEnd: year.to, profitBeforeLevies: profit, lines: lines,
          lock: locking, tr: tr)
      }
      if closed { amounts = [:] }
      busy = false
    }
  }

  /// "Reopen {year}?": reversing entries; the original entries stay in the books.
  private func askReopen(_ close: JSONValue, label: String) {
    let id = close.rid
    let model = self.model
    confirm = AwConfirm(
      title: t("Reopen {year}?", ["year": label]),
      description: t(
        "Reversing entries undo the levies and the transfers to reserves. The original entries stay in the books."),
      confirmLabel: t("Reopen"), danger: true
    ) {
      Task {
        await AwSave.perform(model, done: t("Financial year {year} reopened", ["year": label])) { ctx, tr in
          try AwYearEnd.reopen(ctx, id: id, tr: tr)
        }
      }
    }
  }

  @ViewBuilder
  private func companyCard(
    _ figures: AcYearEndFigures, profile: JSONValue, applies: [AcYearEndProposal], close: JSONValue?
  ) -> some View {
    let format = model.one.format
    let form = KuwaitRules.legalForms.first { $0.value == profile.str("legalForm") }
    let formName = form.map { LanguageStore.shared.isArabic ? $0.labelAr : t($0.label) } ?? ""
    let levies = applies.filter { $0.kind != "statutory_reserve" && $0.kind != "voluntary_reserve" }
    let totalLevies = levies.reduce(0) { $0 + amountOf($1, close) }
    let foreign = AcYearEnd.foreignShare(profile.str("legalForm"), profile.num("foreignOwnershipPercent"))
    Card {
      CardHeader(t("Company"))
      VStack(spacing: 0) {
        AcLineRow(label: t("Legal form"), value: formName, divider: false)
        AcLineRow(label: t("Paid-up capital"), value: figures.capital > 0 ? format.acMoney(figures.capital) : "—")
        AcLineRow(label: t("Foreign ownership"), value: format.percent(foreign))
        AcLineRow(label: t("Statutory reserve"), value: format.acMoney(figures.statutoryReserve))
        if figures.lossesBroughtForward > 0 {
          AcLineRow(label: t("Losses brought forward"), value: format.acMoney(figures.lossesBroughtForward))
        }
        AcLineRow(label: t("Levies and tax"), value: format.acMoney(totalLevies), strong: true)
      }
      VStack(alignment: .leading, spacing: 4) {
        if figures.capitalSource == "books" {
          Text(t("The capital is taken from the capital account."))
        }
        Button {
          Haptics.play(.tap)
          router.push(.settings(section: "company"))
        } label: {
          Text(t("Edit the company profile")).underline()
        }
        .buttonStyle(.plain)
      }
      .font(.web(12))
      .foregroundStyle(palette.slate(500))
      .frame(maxWidth: .infinity, alignment: .leading)
      .padding(.horizontal, 20)
      .padding(.top, 4)
      .padding(.bottom, 16)
    }
  }

  @ViewBuilder
  private func closedYearsCard(_ closes: [JSONValue]) -> some View {
    if !closes.isEmpty {
      let sorted = closes.sorted { $0.str("yearEnd") > $1.str("yearEnd") }
      Card {
        CardHeader(t("Closed years"))
        VStack(spacing: 0) {
          ForEach(sorted.map(Rec.init)) { record in
            let close = record.raw
            AcTapRow(action: { chosen = close.str("yearEnd") }) {
              HStack {
                Text(AcFiscal.label(close.str("yearStart"), close.str("yearEnd")))
                  .font(.web(14, .medium))
                  .foregroundStyle(palette.slate(900))
                Spacer()
                Badge(
                  close.str("status") == "closed" ? t("Closed") : t("Reopened"),
                  tone: close.str("status") == "closed" ? .green : .gray)
              }
              .padding(.horizontal, 20)
              .padding(.vertical, 12)
            }
          }
        }
      }
    }
  }
}
