import SwiftUI

/// The items and inventory pages of Maham One (`src/apps/books/pages/products`
/// and `inventory`), read only: products and services, stock and
/// warehouses, a stock entry, items issued to employees, the stock count
/// sheet and a landed cost. Forms (New item, Adjust stock, Issue items,
/// Allocate landed costs) open their routes, which the web's forms answer.
@MainActor
enum InventoryArea {
  static func page(for route: Route) -> AnyView? {
    switch route {
    case .products: AnyView(InvProductsPage())
    case .inventory: AnyView(InvInventoryPage())
    case .stockEntry(let id): AnyView(InvStockEntryPage(id: id))
    case .stockIssues: AnyView(InvStockIssuesPage())
    case .stockIssue(let id): AnyView(InvStockIssuePage(id: id))
    case .stockCount: AnyView(InvStockCountPage())
    case .landedCost(let id): AnyView(InvLandedCostPage(id: id))
    default: nil
    }
  }
}
