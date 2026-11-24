import SwiftUI
import WidgetKit

/// Everything Maham One puts in the rest of iOS: the Today widget, the two
/// Control Center controls, and the focus Live Activity.
@main
struct MahamWidgetsBundle: WidgetBundle {
  var body: some Widget {
    TodayWidget()
    NewTaskControl()
    TodayControl()
    FocusLiveActivity()
  }
}
