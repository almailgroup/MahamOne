import SafariServices
import SwiftUI

/// The pages that create or change a record (`/invoices/new`,
/// `/clients/:id/edit`, …), until the app writes records itself: each opens
/// the same form of Maham One on the web, inside the app, and what is saved
/// there comes back to this iPhone with the next sync (run as the form
/// closes). Native forms replace these area by area, once each kind's rules
/// match the web's and its records may be written from here.
@MainActor
enum FormBridge {
  static func page(for route: Route) -> AnyView? {
    switch route {
    case .newSalesDocument, .editSalesDocument, .newPurchaseDocument, .editPurchaseDocument,
      .newContact, .editContact, .newPayment, .editPayment, .newRecurring, .newExpense, .newProduct,
      .newStockAdjustment, .newStockIssue, .newLandedCost, .newJournal, .newAsset, .editAsset,
      .newEmployee, .editEmployee, .newLetter, .newCosting, .setup:
      AnyView(FormBridgePage(route: route))
    default:
      nil
    }
  }
}

/// A form of the web, opened inside the app.
struct FormBridgePage: View {
  let route: Route
  @Environment(AppModel.self) private var model
  @Environment(\.palette) private var palette
  @State private var showing = false

  var body: some View {
    WebPage {
      PageHeader(t(route.titleKey))
      Card {
        VStack(spacing: 0) {
          IconView(.squarePen, size: 24)
            .foregroundStyle(palette.primary(600))
            .frame(width: 48, height: 48)
            .background(palette.primary(50), in: Circle())
            .padding(.bottom, 16)
          Text(t("This form opens from Maham One on the web"))
            .font(.web(16, .semibold))
            .foregroundStyle(palette.slate(900))
            .multilineTextAlignment(.center)
          Text(t("It's the same form as on mahamone.com. What you save there shows here within seconds."))
            .font(.web(14))
            .foregroundStyle(palette.slate(500))
            .multilineTextAlignment(.center)
            .frame(maxWidth: 384)
            .padding(.top, 4)
            .padding(.bottom, 20)
          WebButton(t("Open the form"), icon: .externalLink, haptic: .press) { showing = true }
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 24)
        .padding(.vertical, 40)
      }
    }
    .onAppear { showing = true }
    .fullScreenCover(isPresented: $showing, onDismiss: { Task { await model.one.sync() } }) {
      if let url {
        SafariView(url: url).ignoresSafeArea()
      }
    }
  }

  /// The form's address on the web (its routes are after the `#`).
  private var url: URL? {
    guard let base = model.services?.config.webURL else { return nil }
    return URL(string: "#\(route.path)", relativeTo: base)?.absoluteURL
  }
}

/// Safari inside the app, with the app's tint.
struct SafariView: UIViewControllerRepresentable {
  let url: URL
  @Environment(\.palette) private var palette

  func makeUIViewController(context: Context) -> SFSafariViewController {
    let configuration = SFSafariViewController.Configuration()
    configuration.barCollapsingEnabled = true
    let controller = SFSafariViewController(url: url, configuration: configuration)
    controller.preferredControlTintColor = UIColor(palette.primary(600))
    controller.dismissButtonStyle = .done
    return controller
  }

  func updateUIViewController(_ controller: SFSafariViewController, context: Context) {}
}
