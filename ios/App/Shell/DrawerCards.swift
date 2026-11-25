import MahamKit
import SwiftUI

/// The company switcher card at the top of the drawer: surface, a 16pt
/// radius, the hairline ring and a soft shadow; the company's initials on
/// primary-solid (40pt), its name (15pt, 600) and currency, and
/// `ChevronsUpDown`. Its menu lists the
/// person's companies (the current one checked) and "Add company".
struct CompanySwitcher: View {
  let onNavigate: () -> Void
  @Environment(AppModel.self) private var model
  @Environment(ShellRouter.self) private var router
  @Environment(\.palette) private var palette
  @State private var open = false

  var body: some View {
    let business = model.business
    let name = ShellCompany.name(business)
    let shape = RoundedRectangle(cornerRadius: WebRadius.xl, style: .continuous)
    Button {
      Haptics.play(.tap)
      open = true
    } label: {
      HStack(spacing: 12) {
        CompanyInitials(name: name, side: 40)
        VStack(alignment: .leading, spacing: 1) {
          Text(name).font(.web(15, .semibold)).foregroundStyle(palette.slate(900)).lineLimit(1)
          Text(business.currency).font(.web(12)).foregroundStyle(palette.slate(500)).lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        IconView(.chevronsUpDown, size: 16).foregroundStyle(palette.slate(400))
      }
      .padding(.leading, 10)
      .padding(.trailing, 14)
      .padding(.vertical, 10)
      .frame(minHeight: 60)
      .background(palette.surface, in: shape)
      .ring(palette.hairline, in: shape)
      .boxShadow(WebShadow.sm, in: shape)
      .contentShape(shape)
    }
    .buttonStyle(PressedScale())
    .accessibilityLabel(Text(t("Switch company")))
    .dropdownPanel(isPresented: $open, alignment: .start, width: 256) {
      DropdownLabel(t("Companies"))
      ForEach(business.companies) { company in
        DropdownItem(
          ShellCompany.displayName(of: company, profile: nil),
          icon: company.id == business.company?.id ? .check : nil, reservesIcon: true
        ) {
          business.select(company)
          onNavigate()
          router.go(.home)
        }
      }
      DropdownSeparator()
      DropdownItem(t("Add company"), icon: .plus) {
        onNavigate()
        router.go(.setup)
      }
    }
  }
}

/// A company without a logo: its initials on primary-solid, 32pt (or
/// `side`), a quarter of its side for the radius.
struct CompanyInitials: View {
  let name: String
  var side: CGFloat = 32
  @Environment(\.palette) private var palette

  var body: some View {
    let initials = ShellCompany.initials(name)
    Group {
      if initials.isEmpty {
        IconView(.building2, size: 16)
      } else {
        Text(initials).font(.web(side > 32 ? 14 : 12, .semibold))
      }
    }
    .foregroundStyle(palette.onPrimary)
    .frame(width: side, height: side)
    .background(palette.primarySolid, in: RoundedRectangle(cornerRadius: side / 4, style: .continuous))
    .accessibilityHidden(true)
  }
}

/// The signed-in person at the bottom of the drawer: a 36pt primary-100
/// avatar with primary-800 initials, the email and the sync status, and
/// `ChevronsUpDown` for its menu: Sync now, Cloud and sync, Team, Account
/// settings, Sign out.
struct AccountCard: View {
  let onNavigate: () -> Void
  @Environment(AppModel.self) private var model
  @Environment(ShellRouter.self) private var router
  @Environment(\.palette) private var palette
  @State private var open = false
  @State private var signingOut = false

  var body: some View {
    let email = model.session?.user.email ?? ""
    let shape = RoundedRectangle(cornerRadius: WebRadius.xl, style: .continuous)
    Button {
      Haptics.play(.tap)
      open = true
    } label: {
      HStack(spacing: 10) {
        Avatar(email: email)
        VStack(alignment: .leading, spacing: 0) {
          Text(email)
            .font(.web(14, .medium))
            .foregroundStyle(palette.slate(900))
            .lineLimit(1)
            .environment(\.layoutDirection, .leftToRight)
          SyncStatusLine(syncing: model.business.isLoading)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        IconView(.chevronsUpDown, size: 16).foregroundStyle(palette.slate(400))
      }
      .padding(.leading, 8)
      .padding(.trailing, 14)
      .padding(.vertical, 8)
      .frame(minHeight: 52)
      .contentShape(shape)
    }
    .buttonStyle(PressedFill(radius: WebRadius.xl, color: .slate(100)))
    .accessibilityLabel(Text(t("Account: {name}", ["name": email])))
    .dropdownPanel(isPresented: $open, alignment: .start, width: 288) {
      HStack(spacing: 10) {
        Avatar(email: email)
        Text(email)
          .font(.web(12))
          .foregroundStyle(palette.slate(500))
          .lineLimit(1)
          .environment(\.layoutDirection, .leftToRight)
          .frame(maxWidth: .infinity, alignment: .leading)
      }
      .padding(.horizontal, 10)
      .padding(.vertical, 8)
      DropdownSeparator()
      DropdownItem(t("Sync now"), icon: .refreshCw) {
        Task {
          await model.refreshAll()
          model.confirm(t("Sync finished"))
        }
      }
      DropdownItem(t("Cloud and sync"), icon: .cloud) { go(.settings(section: "cloud")) }
      DropdownItem(t("Team"), icon: .usersRound) { go(.settings(section: "team")) }
      DropdownItem(t("Account settings"), icon: .userRound) { go(.settings(section: "account")) }
      DropdownSeparator()
      DropdownItem(t("Sign out"), icon: .logOut) { signingOut = true }
    }
    .webDialog(isPresented: $signingOut, title: t("Sign out?")) {
      Text(t("You can sign in again at any time."))
    } footer: {
      WebButton(t("Cancel"), variant: .outline) { signingOut = false }
      WebButton(t("Sign out")) {
        signingOut = false
        Task {
          await model.signOut()
          model.confirm(t("Signed out"))
        }
      }
    }
  }

  private func go(_ route: Route) {
    onNavigate()
    router.go(route)
  }
}

/// The person's initials on primary-100.
struct Avatar: View {
  let email: String
  @Environment(\.palette) private var palette

  var body: some View {
    Text(email.first.map { String($0).uppercased() } ?? "?")
      .font(.web(12, .semibold))
      .foregroundStyle(palette.primary(800))
      .frame(width: 36, height: 36)
      .background(palette.primary(100), in: Circle())
      .accessibilityHidden(true)
  }
}

/// The sync status in a line: a dot (emerald when synced, sky while
/// syncing) and its words.
struct SyncStatusLine: View {
  let syncing: Bool
  @Environment(\.palette) private var palette

  var body: some View {
    HStack(spacing: 6) {
      Circle()
        .fill(syncing ? palette[.sky(500)] : palette[.emerald(500)])
        .frame(width: 8, height: 8)
      Text(syncing ? t("Syncing…") : t("Synced"))
        .lineLimit(1)
    }
    .font(.web(12))
    .foregroundStyle(palette.slate(600))
  }
}
