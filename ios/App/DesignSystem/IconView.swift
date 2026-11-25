import SwiftUI

/// A lucide icon at a size in points, in the current foreground style:
/// 16 in buttons, 20 in the tab bar, 18 in menu rows (as on the web).
/// Icons that point somewhere face the other way in Arabic.
struct IconView: View {
  let icon: Icon
  var size: CGFloat

  init(_ icon: Icon, size: CGFloat = 16) {
    self.icon = icon
    self.size = size
  }

  var body: some View {
    Image(icon.rawValue)
      .renderingMode(.template)
      .resizable()
      .interpolation(.high)
      .aspectRatio(contentMode: .fit)
      .frame(width: size, height: size)
      .flipsForRightToLeftLayoutDirection(icon.mirrorsInRightToLeft)
      .accessibilityHidden(true)
  }
}

/// The icon spinning, as Tailwind's `animate-spin` turns `Loader2`: once a second.
struct SpinningIcon: View {
  var icon: Icon = .loader2
  var size: CGFloat = 16

  var body: some View {
    TimelineView(.animation) { context in
      let turn = context.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 1)
      IconView(icon, size: size)
        .rotationEffect(.degrees(turn * 360))
    }
    .frame(width: size, height: size)
    .accessibilityHidden(true)
  }
}

extension Icon {
  /// The icon as a view: `Icon.house.view(20)`.
  @MainActor
  func view(_ size: CGFloat = 16) -> IconView { IconView(self, size: size) }
}
