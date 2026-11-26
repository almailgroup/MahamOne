import SwiftUI

/// The page for a web address (`src/app/routes.tsx`): Home and the
/// documents here, every other area's pages from `AreaPages`.
struct RouteView: View {
  let route: Route

  var body: some View {
    switch route {
    case .home:
      HomePage()
    case .notFound:
      NotFoundPage()
    case .salesDocuments(let kind):
      DocumentListPage(type: DocType(kind))
    case .salesDocument(let kind, let id):
      DocumentPage(type: DocType(kind), id: id)
    case .purchaseDocuments(let kind):
      DocumentListPage(type: DocType(kind))
    case .purchaseDocument(let kind, let id):
      DocumentPage(type: DocType(kind), id: id)
    default:
      if let page = AreaPages.page(for: route) {
        page
      } else {
        PlaceholderPage(title: t(route.titleKey))
      }
    }
  }
}

/// A screen of the web not built natively yet: its title, and the web's
/// empty state saying it is coming.
struct PlaceholderPage: View {
  let title: String

  var body: some View {
    WebPage {
      PageHeader(title)
      Card {
        WebEmptyState(icon: .hourglass, title: t("This screen is coming in the next update."))
      }
    }
  }
}

/// The web's "Page not found", with the way home.
struct NotFoundPage: View {
  @Environment(ShellRouter.self) private var router

  var body: some View {
    WebPage {
      Card {
        WebEmptyState(
          icon: .fileQuestion, title: t("Page not found"),
          description: t("The page you were looking for doesn't exist or has moved.")
        ) {
          WebButton(t("Go to the home page")) { router.go(.home) }
        }
      }
    }
  }
}
