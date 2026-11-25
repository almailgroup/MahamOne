import SwiftUI

/// One segment: its value, label and an optional count.
struct SegmentOption<Value: Hashable>: Identifiable {
  let value: Value
  let label: String
  var count: Int?
  var id: Value { value }

  init(_ value: Value, _ label: String, count: Int? = nil) {
    self.value = value
    self.label = label
    self.count = count
  }
}

/// The web's `Segmented` (status filters, small toggles): a slate-100 track
/// with an 8pt radius and 4pt padding; segments with a 6pt radius, at least
/// 40pt tall, 14pt weight 500; the selected one surface, slate-900 and
/// shadow-sm. It hugs its segments, and scrolls sideways when they don't fit.
/// Changing segment plays the selection haptic.
struct Segmented<Value: Hashable>: View {
  @Binding var selection: Value
  let options: [SegmentOption<Value>]
  var small: Bool
  @Environment(\.palette) private var palette

  init(selection: Binding<Value>, options: [SegmentOption<Value>], small: Bool = false) {
    _selection = selection
    self.options = options
    self.small = small
  }

  var body: some View {
    ViewThatFits(in: .horizontal) {
      track
      ScrollViewReader { proxy in
        ScrollView(.horizontal, showsIndicators: false) {
          track
        }
        .clipShape(RoundedRectangle(cornerRadius: WebRadius.md, style: .continuous))
        .onChange(of: selection, initial: true) { _, value in
          withAnimation(WebMotion.standard) { proxy.scrollTo(value, anchor: .center) }
        }
      }
    }
  }

  private var track: some View {
    HStack(spacing: 0) {
      ForEach(options) { option in
        segment(option).id(option.value)
      }
    }
    .padding(4)
    .background(palette.slate(100), in: RoundedRectangle(cornerRadius: WebRadius.md, style: .continuous))
    .fixedSize()
  }

  private func segment(_ option: SegmentOption<Value>) -> some View {
    let selected = option.value == selection
    let shape = RoundedRectangle(cornerRadius: WebRadius.sm, style: .continuous)
    return Button {
      guard option.value != selection else { return }
      Haptics.play(.selection)
      withAnimation(WebMotion.standard) { selection = option.value }
    } label: {
      HStack(spacing: 6) {
        Text(option.label).lineLimit(1)
        if let count = option.count {
          Text(String(count))
            .font(.web(12, tabular: true))
            .padding(.horizontal, 6)
            .background(selected ? palette.slate(100) : palette.slate(200).opacity(0.7), in: Capsule())
            .foregroundStyle(selected ? palette.slate(700) : palette.slate(600))
        }
      }
      .font(.web(small ? 12 : 14, .medium))
      .foregroundStyle(selected ? palette.slate(900) : palette.slate(600))
      .padding(.horizontal, small ? 8 : 12)
      .frame(minHeight: small ? 36 : 40)
      .background {
        if selected {
          shape.fill(palette.surface).boxShadow(WebShadow.sm, in: shape)
        }
      }
      .contentShape(shape)
    }
    .buttonStyle(PressedFill(radius: WebRadius.sm, color: .slate(200)))
    .accessibilityAddTraits(selected ? .isSelected : [])
  }
}
