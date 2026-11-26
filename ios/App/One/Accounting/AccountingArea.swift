import SwiftUI

/// The accounting and reports pages of Maham One: the Books dashboard, the
/// chart of accounts, journals, fixed assets, the year-end close, banking,
/// VAT and the reports, read only. Forms (`/journals/new`, `/assets/new`,
/// `/assets/:id/edit`) stay with `FormBridge`.
@MainActor
enum AccountingArea {
  static func page(for route: Route) -> AnyView? {
    switch route {
    case .booksDashboard: AnyView(AcDashboardPage())
    case .accounts: AnyView(AcChartPage())
    case .journals: AnyView(AcJournalsPage())
    case .journal(let id): AnyView(AcJournalPage(id: id))
    case .assets: AnyView(AcAssetsPage())
    case .asset(let id): AnyView(AcAssetPage(id: id))
    case .yearEnd: AnyView(AcYearEndPage())
    case .banking: AnyView(AcBankingPage())
    case .bankAccount(let id): AnyView(AcBankAccountPage(id: id))
    case .vat: AnyView(AcVatPage())
    case .vatReturn(let start): AnyView(AcVatReturnPage(start: start))
    case .reports: AnyView(AcReportsPage())
    case .report(let name): AnyView(AcReportPage(name: name))
    default: nil
    }
  }
}
