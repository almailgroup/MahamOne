import SwiftUI

/// A day as the web keeps it: "yyyy-MM-dd", in the Gregorian calendar.
struct CalendarDay: Hashable, Comparable, Sendable {
  let year: Int
  let month: Int
  let day: Int

  private static var calendar: Calendar {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = .current
    return calendar
  }

  init(year: Int, month: Int, day: Int) {
    self.year = year
    self.month = month
    self.day = day
  }

  init(_ date: Date) {
    let parts = Self.calendar.dateComponents([.year, .month, .day], from: date)
    self.init(year: parts.year ?? 2000, month: parts.month ?? 1, day: parts.day ?? 1)
  }

  /// "2026-11-25"; nil for anything else or a day that doesn't exist.
  init?(iso: String) {
    let parts = iso.split(separator: "-").map { Int($0) }
    guard parts.count == 3, let y = parts[0], let m = parts[1], let d = parts[2],
      Self.isValid(year: y, month: m, day: d)
    else { return nil }
    self.init(year: y, month: m, day: d)
  }

  static var today: CalendarDay { CalendarDay(Date()) }

  static func isValid(year: Int, month: Int, day: Int) -> Bool {
    guard (1...12).contains(month), day >= 1, year >= 1 else { return false }
    return day <= daysIn(year: year, month: month)
  }

  static func daysIn(year: Int, month: Int) -> Int {
    switch month {
    case 2: (year % 4 == 0 && year % 100 != 0) || year % 400 == 0 ? 29 : 28
    case 4, 6, 9, 11: 30
    default: 31
    }
  }

  var iso: String {
    String(format: "%04d-%02d-%02d", year, month, day)
  }

  /// dd/MM/yyyy, the web's date format (Kuwait).
  var display: String {
    String(format: "%02d/%02d/%04d", day, month, year)
  }

  var date: Date {
    Self.calendar.date(from: DateComponents(year: year, month: month, day: day, hour: 12)) ?? Date()
  }

  /// 1 Sunday … 7 Saturday.
  var weekday: Int { Self.calendar.component(.weekday, from: date) }

  func adding(days: Int) -> CalendarDay {
    CalendarDay(Self.calendar.date(byAdding: .day, value: days, to: date) ?? date)
  }

  func adding(months: Int) -> CalendarDay {
    var y = year
    var m = month + months
    while m > 12 {
      m -= 12
      y += 1
    }
    while m < 1 {
      m += 12
      y -= 1
    }
    return CalendarDay(year: y, month: m, day: min(day, Self.daysIn(year: y, month: m)))
  }

  var firstOfMonth: CalendarDay { CalendarDay(year: year, month: month, day: 1) }
  var endOfMonth: CalendarDay { CalendarDay(year: year, month: month, day: Self.daysIn(year: year, month: month)) }

  /// The 42 days a month's calendar shows, from the Sunday on or before the 1st.
  var monthGrid: [CalendarDay] {
    let first = firstOfMonth
    let start = first.adding(days: -(first.weekday - 1))
    return (0..<42).map { start.adding(days: $0) }
  }

  static func < (a: CalendarDay, b: CalendarDay) -> Bool {
    (a.year, a.month, a.day) < (b.year, b.month, b.day)
  }

  /// What can be typed, as on the web: 31/12/2026, 3/10, 3/10/26, "+7",
  /// "-1", "today". Arabic digits count too.
  static func parse(_ text: String, today: CalendarDay = .today) -> CalendarDay? {
    let input = String(
      text.trimmingCharacters(in: .whitespaces).lowercased().unicodeScalars.map { scalar -> Character in
        switch scalar.value {
        case 0x0660...0x0669: Character(String(scalar.value - 0x0660))
        case 0x06F0...0x06F9: Character(String(scalar.value - 0x06F0))
        default: Character(scalar)
        }
      })
    if input.isEmpty { return nil }
    if ["today", "t", "اليوم"].contains(input) { return today }
    if let first = input.first, first == "+" || first == "-", let days = Int(input.dropFirst()) {
      return today.adding(days: first == "+" ? days : -days)
    }
    let numbers = input.split(whereSeparator: { "/.- ".contains($0) }).compactMap { Int($0) }
    guard numbers.count == 2 || numbers.count == 3 else { return nil }
    var year = numbers.count == 3 ? numbers[2] : today.year
    if year < 100 { year += 2000 }
    let found = CalendarDay(year: year, month: numbers[1], day: numbers[0])
    return isValid(year: found.year, month: found.month, day: found.day) ? found : nil
  }
}

/// The web's date field (`src/components/ui/date-field.tsx`): the date in
/// the company's format (dd/MM/yyyy), typed or picked from a calendar that
/// opens from the `CalendarDays` button. Keeps "yyyy-MM-dd", or "" when
/// cleared (a required date can't be cleared).
struct DateField: View {
  @Binding var value: String
  var min: String?
  var max: String?
  var required: Bool
  var placeholder: String
  @State private var text = ""
  @State private var open = false
  @FocusState private var focused: Bool
  @Environment(\.palette) private var palette

  init(
    value: Binding<String>, min: String? = nil, max: String? = nil, required: Bool = false,
    placeholder: String = "dd/mm/yyyy"
  ) {
    _value = value
    self.min = min
    self.max = max
    self.required = required
    self.placeholder = placeholder
  }

  private var shownValue: String { CalendarDay(iso: value)?.display ?? "" }

  var body: some View {
    HStack(spacing: 0) {
      ZStack(alignment: .leading) {
        if text.isEmpty {
          Text(placeholder).foregroundStyle(palette.slate(400)).allowsHitTesting(false)
        }
        TextField("", text: $text)
          .keyboardType(.numbersAndPunctuation)
          .focused($focused)
          .submitLabel(.done)
          .onSubmit(settle)
      }
      .padding(.leading, 12)
      Button {
        Haptics.play(.tap)
        open = true
      } label: {
        IconView(.calendarDays, size: 16)
          .foregroundStyle(palette.slate(500))
          .frame(width: 44, height: 44)
          .contentShape(Rectangle())
      }
      .buttonStyle(.plain)
      .accessibilityLabel(Text(t("Choose a date")))
      .anchoredPanel(isPresented: $open, alignment: .end, width: 304) {
        DateCalendar(
          selected: CalendarDay(iso: value), earliest: min.flatMap(CalendarDay.init(iso:)),
          latest: max.flatMap(CalendarDay.init(iso:))
        ) { picked in
          commit(picked.iso)
          text = picked.display
        }
      }
    }
    .modifier(InputChrome(focused: focused))
    .onAppear { text = shownValue }
    .onChange(of: value) { _, _ in
      if !focused { text = shownValue }
    }
    .onChange(of: text) { _, typed in
      // A full date is used at once; anything shorter when leaving the field.
      if focused, typed.count >= 8, let parsed = CalendarDay.parse(typed) { commit(parsed.iso) }
    }
    .onChange(of: focused) { _, now in
      if !now { settle() }
    }
  }

  private func commit(_ next: String) {
    if next != value { value = next }
  }

  private func settle() {
    let typed = text.trimmingCharacters(in: .whitespaces)
    if typed.isEmpty {
      if !required { commit("") }
    } else if let parsed = CalendarDay.parse(typed) {
      commit(parsed.iso)
    }
    text = shownValue
  }
}

/// The calendar: 19rem wide, starting on Sunday, 6 rows of 36pt days, the
/// weekend (Friday and Saturday) in slate-500, and the quick picks below.
private struct DateCalendar: View {
  let selected: CalendarDay?
  let earliest: CalendarDay?
  let latest: CalendarDay?
  let onPick: (CalendarDay) -> Void
  @State private var month: CalendarDay
  @Environment(\.palette) private var palette
  @Environment(\.locale) private var locale
  @Environment(\.layoutDirection) private var direction
  @Environment(\.dismissPanel) private var dismissPanel

  init(
    selected: CalendarDay?, earliest: CalendarDay?, latest: CalendarDay?,
    onPick: @escaping (CalendarDay) -> Void
  ) {
    self.selected = selected
    self.earliest = earliest
    self.latest = latest
    self.onPick = onPick
    _month = State(initialValue: (selected ?? .today).firstOfMonth)
  }

  var body: some View {
    let today = CalendarDay.today
    let days = month.monthGrid
    let columns = Array(repeating: GridItem(.flexible(), spacing: 0), count: 7)
    VStack(spacing: 0) {
      HStack(spacing: 8) {
        monthButton(.chevronLeft, label: t("Previous month")) { month = month.adding(months: -1) }
        Text(title)
          .font(.web(14, .semibold))
          .foregroundStyle(palette.slate(900))
          .frame(maxWidth: .infinity)
        monthButton(.chevronRight, label: t("Next month")) { month = month.adding(months: 1) }
      }
      .padding(.bottom, 8)
      LazyVGrid(columns: columns, spacing: 2) {
        ForEach(0..<7, id: \.self) { index in
          Text(weekdaySymbol(days[index].weekday))
            .font(.web(12, .medium))
            .foregroundStyle(palette.slate(500))
            .padding(.vertical, 4)
        }
        ForEach(days, id: \.self) { day in
          dayButton(day, today: today)
        }
      }
      VStack(spacing: 0) {
        Rectangle().fill(palette.slate(100)).frame(height: 1).padding(.bottom, 12)
        LazyVGrid(columns: [GridItem(.flexible(), spacing: 6), GridItem(.flexible(), spacing: 6)], spacing: 6) {
          quickPick(t("Today"), today)
          quickPick(tp(7, "In {count} day", "In {count} days"), today.adding(days: 7))
          quickPick(tp(30, "In {count} day", "In {count} days"), today.adding(days: 30))
          quickPick(t("End of month"), today.endOfMonth)
        }
      }
      .padding(.top, 12)
    }
    .padding(12)
    .background(palette.surface, in: RoundedRectangle(cornerRadius: WebRadius.lg, style: .continuous))
    .border(palette.slate(200), in: RoundedRectangle(cornerRadius: WebRadius.lg, style: .continuous))
    .boxShadow(WebShadow.lg, in: RoundedRectangle(cornerRadius: WebRadius.lg, style: .continuous))
  }

  private var title: String {
    let formatter = DateFormatter()
    formatter.locale = locale
    formatter.setLocalizedDateFormatFromTemplate("MMMMy")
    return formatter.string(from: month.date)
  }

  private func weekdaySymbol(_ weekday: Int) -> String {
    var calendar = Calendar(identifier: .gregorian)
    calendar.locale = locale
    let symbols = direction == .rightToLeft ? calendar.veryShortWeekdaySymbols : calendar.shortWeekdaySymbols
    let index = weekday - 1
    return symbols.indices.contains(index) ? symbols[index] : ""
  }

  private func isDisabled(_ day: CalendarDay) -> Bool {
    if let earliest, day < earliest { return true }
    if let latest, day > latest { return true }
    return false
  }

  private func pick(_ day: CalendarDay) {
    Haptics.play(.selection)
    onPick(day)
    dismissPanel()
  }

  /// Previous and next month: 44pt round Liquid Glass buttons.
  private func monthButton(_ icon: Icon, label: String, action: @escaping () -> Void) -> some View {
    GlassIconButton(icon, label: label, iconSize: 16, color: .slate(600), haptic: .selection) {
      withAnimation(WebMotion.standard) { action() }
    }
  }

  private func dayButton(_ day: CalendarDay, today: CalendarDay) -> some View {
    let isSelected = day == selected
    let isToday = day == today
    let inMonth = day.month == month.month && day.year == month.year
    let weekend = day.weekday == 6 || day.weekday == 7
    let disabled = isDisabled(day)
    let color: Color =
      isSelected
      ? palette.onPrimary
      : isToday ? palette.primary(700) : (inMonth && !weekend ? palette.slate(800) : palette.slate(500))
    return Button {
      pick(day)
    } label: {
      Text(String(day.day))
        .font(.web(14, isSelected || isToday ? .semibold : .regular, tabular: true))
        .foregroundStyle(color)
        .frame(width: 36, height: 36)
        .background {
          if isSelected {
            Circle().fill(palette.primarySolid)
          } else if isToday {
            Circle().strokeBorder(palette.primary(300), lineWidth: 1)
          }
        }
        .contentShape(Circle())
    }
    .buttonStyle(PressedFill(radius: 18))
    .disabled(disabled)
    .opacity(disabled ? 0.3 : 1)
    .accessibilityLabel(Text(day.date.formatted(Date.FormatStyle(date: .complete, time: .omitted).locale(locale))))
    .accessibilityAddTraits(isSelected ? .isSelected : [])
  }

  /// Today, In 7 days…: small Liquid Glass buttons, 44pt tall.
  private func quickPick(_ label: String, _ day: CalendarDay) -> some View {
    Button {
      pick(day)
    } label: {
      Text(label)
        .font(.web(12, .medium))
        .foregroundStyle(palette.slate(700))
        .lineLimit(1)
        .minimumScaleFactor(0.8)
        .frame(maxWidth: .infinity, minHeight: 44)
        .padding(.horizontal, 8)
    }
    .buttonStyle(.webGlass(.rounded(WebRadius.sm)))
    .disabled(isDisabled(day))
    .opacity(isDisabled(day) ? 0.8 : 1)
  }
}

/// A plain button that takes a slate fill while pressed (the web's hover and
/// active backgrounds): rows, tiles, menu items. The Taptic Engine wakes as
/// it is pressed, so the action's haptic is felt at once.
struct PressedFill: ButtonStyle {
  var radius: CGFloat = WebRadius.md
  var color: Token = .slate(100)

  func makeBody(configuration: Configuration) -> some View {
    PressedFillBody(configuration: configuration, radius: radius, color: color)
  }
}

private struct PressedFillBody: View {
  let configuration: ButtonStyleConfiguration
  let radius: CGFloat
  let color: Token
  @Environment(\.palette) private var palette

  var body: some View {
    configuration.label
      .background(
        configuration.isPressed ? palette.color(color) : Color.clear,
        in: RoundedRectangle(cornerRadius: radius, style: .continuous))
      .onChange(of: configuration.isPressed) { _, now in
        if now { Haptics.prepare() }
      }
  }
}

/// A card that is a button (the company switcher): pressed, it shrinks a
/// little and dims.
struct PressedScale: ButtonStyle {
  func makeBody(configuration: Configuration) -> some View {
    PressedScaleBody(configuration: configuration)
  }
}

private struct PressedScaleBody: View {
  let configuration: ButtonStyleConfiguration
  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  var body: some View {
    let pressed = configuration.isPressed
    configuration.label
      .scaleEffect(pressed && !reduceMotion ? 0.98 : 1)
      .opacity(pressed ? 0.85 : 1)
      .animation(WebMotion.standard, value: pressed)
      .onChange(of: pressed) { _, now in
        if now { Haptics.prepare() }
      }
  }
}
