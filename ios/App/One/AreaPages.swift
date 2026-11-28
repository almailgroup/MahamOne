import SwiftUI

/// The pages of each area of Maham One, by route. Each area answers the
/// routes it has a page for (`<Area>Area.page(for:)`) and nil for the rest;
/// `RouteView` asks them in turn.
@MainActor
enum AreaPages {
  /// Every area's page maker.
  static let makers: [@MainActor (Route) -> AnyView?] = [
    // The forms first: they answer the new and edit routes.
    DocumentsWriteArea.page(for:),
    InventoryWriteArea.page(for:),
    AccountingWriteArea.page(for:),
    FormBridge.page(for:),
    InventoryArea.page(for:),
    ContactsArea.page(for:),
    SuiteArea.page(for:),
    AccountingArea.page(for:),
    PeopleArea.page(for:),
  ]

  /// The page an area has for `route`, if any.
  static func page(for route: Route) -> AnyView? {
    for maker in makers {
      if let page = maker(route) { return page }
    }
    return nil
  }
}
