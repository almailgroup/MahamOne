#if DEBUG
  // Preview mode: the app as a signed-in owner sees it, with made-up data and
  // no network, opened on a given page and overlay, for screenshots without
  // a device or an account (ios/scripts/screenshots.sh and the "iOS
  // screenshots" workflow). Debug builds only: none of this, and none of the
  // hooks that call it (each marked "Preview mode"), is in a Release build.
  //
  // Launch arguments (Xcode: Product → Scheme → Edit Scheme → Run →
  // Arguments; or `xcrun simctl launch booted com.almailgroup.mahamone …`):
  //
  //   -MahamPreview 1          on: signed in as the sample person, in the
  //                            sample company (PreviewData), no network
  //   -MahamRoute /invoices    the page, as a web address (default `/`)
  //   -MahamOverlay drawer     none | drawer | create | switcher | search | theme
  //                            (theme opens the drawer; its "Theme" button is
  //                            then tapped by the script, see PreviewOverlay.swift)
  //   -MahamDepartment tasks   one (Maham One, default) | tasks (Maham Tasks)
  //   -MahamTheme midnight     a theme (ThemeID's raw value: classic, gulf, deep-sea…)
  //   -MahamScheme dark        light | dark | system
  //   -MahamLanguage ar        en | ar
  //
  // The last three also work without -MahamPreview (the sign-in screen in
  // Arabic, say). With -MahamPreview, what isn't given is Classic, light and
  // English, whatever was chosen before. They are saved, as a choice in the
  // app would be.

  import Foundation
  import MahamKit
  import SwiftUI

  /// What a launch asks preview mode for.
  struct PreviewOptions: Sendable, Equatable {
    enum Overlay: String, Sendable, CaseIterable {
      case none, drawer, create, switcher, search, theme
    }

    enum Scheme: String, Sendable {
      case light, dark, system

      var mode: ThemeMode {
        switch self {
        case .light: .light
        case .dark: .dark
        case .system: .system
        }
      }
    }

    /// `-MahamPreview 1`.
    var enabled = false
    var route = "/"
    var overlay: Overlay = .none
    var department: Department = .one
    var theme: ThemeID?
    var scheme: Scheme?
    var language: Language?

    init(arguments: [String]) {
      /// The word after `-Maham<name>`.
      func value(_ name: String) -> String? {
        guard let index = arguments.firstIndex(of: "-Maham" + name), index + 1 < arguments.count else { return nil }
        return arguments[index + 1].trimmingCharacters(in: .whitespaces)
      }
      enabled = ["1", "yes", "true"].contains(value("Preview")?.lowercased() ?? "")
      if let route = value("Route"), !route.isEmpty {
        self.route = route.hasPrefix("/") ? route : "/" + route
      }
      overlay = value("Overlay").flatMap { Overlay(rawValue: $0.lowercased()) } ?? .none
      department = value("Department").flatMap { Department(rawValue: $0.lowercased()) } ?? .one
      theme = value("Theme").flatMap { ThemeID(rawValue: $0.lowercased()) }
      scheme = value("Scheme").flatMap { Scheme(rawValue: $0.lowercased()) }
      language = value("Language").flatMap { Language(rawValue: $0.lowercased()) }
    }
  }

  /// Preview mode, as this launch asked for it.
  enum PreviewMode {
    static let options = PreviewOptions(arguments: ProcessInfo.processInfo.arguments)

    /// `-MahamPreview 1` was given.
    static var isOn: Bool { options.enabled }

    /// The made-up services the app runs on in preview mode (nil when it is
    /// off): every request answered "offline", the sample data in a cache of
    /// its own. Built once, before the model's stores read their cache.
    static let services: AppServices? = isOn ? PreviewData.makeServices(language: options.language ?? .en) : nil

    /// The theme, light or dark and language the launch asks for, before the
    /// first screen is drawn.
    @MainActor
    static func applyAppearance() {
      if let language = options.language ?? (isOn ? Language.en : nil) {
        LanguageStore.shared.language = language
      }
      guard isOn || options.theme != nil || options.scheme != nil else { return }
      let store = ThemeStore.shared
      if isOn {
        store.lightTheme = ThemeID.defaultLight
        store.darkTheme = ThemeID.defaultDark
      }
      if let theme = options.theme {
        if theme.scheme == .dark { store.darkTheme = theme } else { store.lightTheme = theme }
      }
      if let mode = Self.mode { store.mode = mode }
    }

    /// Light or dark as asked; else as the theme is; else, in preview mode, light.
    private static var mode: ThemeMode? {
      if let scheme = options.scheme { return scheme.mode }
      if let theme = options.theme { return theme.scheme == .dark ? ThemeMode.dark : ThemeMode.light }
      return isOn ? ThemeMode.light : nil
    }
  }
#endif
