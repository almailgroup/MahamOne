import CoreText
import SwiftUI
import os

/// The weights the web uses (400, 500, 600, 700).
enum FontWeight: Hashable, Sendable {
  case regular, medium, semibold, bold

  /// The Inter file's PostScript name (Resources/Fonts).
  var inter: String {
    switch self {
    case .regular: "Inter-Regular"
    case .medium: "Inter-Medium"
    case .semibold: "Inter-SemiBold"
    case .bold: "Inter-Bold"
    }
  }

  /// IBM Plex Sans Arabic of the same weight.
  var plexArabic: String {
    switch self {
    case .regular: "IBMPlexSansArabic-Regular"
    case .medium: "IBMPlexSansArabic-Medium"
    case .semibold: "IBMPlexSansArabic-SemiBold"
    case .bold: "IBMPlexSansArabic-Bold"
    }
  }
}

/// The web's type: Inter with the features `cv11` and `ss01`, and IBM Plex
/// Sans Arabic for Arabic letters. As in the web's font stack
/// (`'Inter Variable', 'IBM Plex Sans Arabic', …`), each letter takes the
/// first font that has it, so an Arabic name in English mode and an English
/// word in Arabic mode both look as they do on the web. Amounts use tabular
/// figures (`tabular: true`). Sizes are the web's pixels, in points.
enum WebFont {
  private struct Key: Hashable, Sendable {
    let size: CGFloat
    let weight: FontWeight
    let tabular: Bool
  }

  private static let cache = OSAllocatedUnfairLock<[Key: Font]>(initialState: [:])

  static func font(_ size: CGFloat, _ weight: FontWeight = .regular, tabular: Bool = false) -> Font {
    let key = Key(size: size, weight: weight, tabular: tabular)
    if let found = cache.withLock({ $0[key] }) { return found }
    let font = Font(make(key))
    cache.withLock { $0[key] = font }
    return font
  }

  private static func make(_ key: Key) -> CTFont {
    let tag = kCTFontOpenTypeFeatureTag as String
    let value = kCTFontOpenTypeFeatureValue as String
    var features: [[String: Any]] = [
      [tag: "cv11", value: 1],
      [tag: "ss01", value: 1],
    ]
    if key.tabular { features.append([tag: "tnum", value: 1]) }
    let arabic = CTFontDescriptorCreateWithNameAndSize(key.weight.plexArabic as CFString, key.size)
    let attributes: [String: Any] = [
      kCTFontNameAttribute as String: key.weight.inter,
      kCTFontSizeAttribute as String: key.size,
      kCTFontFeatureSettingsAttribute as String: features,
      kCTFontCascadeListAttribute as String: [arabic],
    ]
    let descriptor = CTFontDescriptorCreateWithAttributes(attributes as CFDictionary)
    return CTFontCreateWithFontDescriptor(descriptor, key.size, nil)
  }
}

extension Font {
  /// The web's font at a size and weight: `.font(.web(14, .medium))`.
  static func web(_ size: CGFloat, _ weight: FontWeight = .regular, tabular: Bool = false) -> Font {
    WebFont.font(size, weight, tabular: tabular)
  }
}

/// The text styles of `mobile-design.md`, with the web's line heights.
enum WebTextStyle: Sendable {
  /// 24/32, 600, −0.025em, slate-900.
  case pageTitle
  /// Card, dialog and sheet titles: 16/24, 600, slate-900.
  case cardTitle
  /// Home section titles: 14/20, 600, slate-500.
  case sectionTitle
  /// Body and table text: 14/20.
  case body
  /// A phone list row's title: 16, 500, slate-900.
  case listTitle
  /// 12/16, slate-500.
  case meta
  /// 12, 500, uppercase, +0.025em, slate-500.
  case tableHeader
  /// Badges and tab labels: 12, 500.
  case badge

  var size: CGFloat {
    switch self {
    case .pageTitle: 24
    case .cardTitle, .listTitle: 16
    case .sectionTitle, .body: 14
    case .meta, .tableHeader, .badge: 12
    }
  }

  var lineHeight: CGFloat {
    switch self {
    case .pageTitle: 32
    case .cardTitle, .listTitle: 24
    case .sectionTitle, .body: 20
    case .meta, .tableHeader, .badge: 16
    }
  }

  var weight: FontWeight {
    switch self {
    case .pageTitle, .cardTitle, .sectionTitle: .semibold
    case .listTitle, .tableHeader, .badge: .medium
    case .body, .meta: .regular
    }
  }

  /// Letter spacing in em; normal in Arabic, where it breaks the joins.
  var tracking: CGFloat {
    switch self {
    case .pageTitle: -0.025
    case .tableHeader: 0.025
    default: 0
    }
  }

  var color: Token? {
    switch self {
    case .pageTitle, .cardTitle, .listTitle: .slate(900)
    case .sectionTitle, .meta, .tableHeader: .slate(500)
    case .body, .badge: nil
    }
  }
}

private struct WebTextModifier: ViewModifier {
  let style: WebTextStyle
  @Environment(\.palette) private var palette
  @Environment(\.layoutDirection) private var direction

  func body(content: Content) -> some View {
    // Inter's own line is 1.21 of its size; CSS spreads the rest of the
    // line height above and below the text.
    let extra = max(0, style.lineHeight - style.size * 1.21)
    let styled =
      content
      .font(.web(style.size, style.weight))
      .tracking(direction == .rightToLeft ? 0 : style.tracking * style.size)
      .lineSpacing(extra)
      .padding(.vertical, extra / 2)
      .textCase(style == .tableHeader ? .uppercase : nil)
    if let color = style.color {
      styled.foregroundStyle(palette.color(color))
    } else {
      styled
    }
  }
}

extension View {
  /// One of the web's text styles: font, line height, tracking and colour.
  func webText(_ style: WebTextStyle) -> some View {
    modifier(WebTextModifier(style: style))
  }
}
