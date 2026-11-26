import MahamKit
import SwiftUI

// `/year-end` (src/apps/books/pages/accounting/year-end.tsx), read only: the
// profit for a financial year, the statutory reserve and the levies as the
// web proposes them (or as the year was closed with), and the closed years.

struct AcYearEndPage: View {
  @Environment(AppModel.self) private var model
  @Environment(ShellRouter.self) private var router
  @Environment(\.palette) private var palette
  @State private var chosen: String?

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
      if let close { closedCard(close) }
      companyCard(figures, profile: profile, applies: applies, close: close)
      closedYearsCard(closes)
    }
  }

  // MARK: Choosing the year

  private func selectedYear(_ years: [AcRange], closedYears: Set<String>, today: String) -> AcRange {
    if let chosen, let found = years.first(where: { $0.to == chosen }) { return found }
    if let open = years.first(where: { $0.to < today && !closedYears.contains($0.to) }) { return open }
    return years.first ?? AcRange(from: today, to: today)
  }

  private func yearBinding(_ year: AcRange) -> Binding<String> {
    Binding(get: { chosen ?? year.to }, set: { chosen = $0 })
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

  private func amountOf(_ proposal: AcYearEndProposal, _ close: JSONValue?) -> Int {
    guard let close else { return proposal.amount }
    let line = close.list("lines").first { $0.str("kind") == proposal.kind }
    return AcLedger.minor(line?.num("amount") ?? 0, model.one.acBooks.precision)
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
          proposalRow(applies[index], amount: amountOf(applies[index], close), figures: figures, rates: rates)
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
    _ proposal: AcYearEndProposal, amount: Int, figures: AcYearEndFigures, rates: AcLevyRates
  ) -> some View {
    let format = model.one.format
    return HStack(alignment: .top, spacing: 12) {
      VStack(alignment: .leading, spacing: 2) {
        Text(t(AcYearEnd.label(proposal.kind))).font(.web(14, .medium)).foregroundStyle(palette.slate(900))
        Text(explanation(proposal, figures: figures, rates: rates, format: format))
          .font(.web(12))
          .foregroundStyle(palette.slate(500))
      }
      .frame(maxWidth: .infinity, alignment: .leading)
      Text(format.acMoney(amount))
        .font(.web(14, .semibold, tabular: true))
        .foregroundStyle(palette.slate(900))
        .environment(\.layoutDirection, .leftToRight)
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

  private func closedCard(_ close: JSONValue) -> some View {
    let format = model.one.format
    return Card {
      HStack(spacing: 8) {
        IconView(.circleCheck, size: 16)
        Text(t("Closed on {date}", ["date": format.dateTime(close.text("createdAt"))]))
        if close.text("lockedTo") != nil { Badge(t("Locked")) }
      }
      .font(.web(14))
      .foregroundStyle(palette[.emerald(700)])
      .padding(20)
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
