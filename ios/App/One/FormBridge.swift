import SwiftUI

/// The pages that create or change a record (`/invoices/new`,
/// `/clients/:id/edit`, …) belong to each area, which answers them with its
/// native form once that kind of record can be saved here
/// (`OneWritable`). The app never opens the web for them.
@MainActor
enum FormBridge {
  static func page(for route: Route) -> AnyView? { nil }
}
