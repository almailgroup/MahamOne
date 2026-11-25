import SwiftUI

/// The page for a web address (`src/app/routes.tsx`). Home is built; every
/// other page shows the placeholder until its stage fills it in here.
struct RouteView: View {
  let route: Route

  var body: some View {
    switch route {
    case .home:
      HomePage()
    case .notFound:
      NotFoundPage()
    default:
      PlaceholderPage(title: t(route.titleKey))
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
