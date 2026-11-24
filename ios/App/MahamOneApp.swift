import MahamKit
import SwiftUI

@main
struct MahamOneApp: App {
  var body: some Scene {
    WindowGroup {
      BootView()
    }
  }
}

/// A first screen, to prove the build: replaced by the real app shell.
struct BootView: View {
  var body: some View {
    ZStack {
      Color("Shell").ignoresSafeArea()
      VStack(spacing: 16) {
        Image(systemName: "square.grid.2x2.fill")
          .font(.system(size: 44))
          .foregroundStyle(.tint)
        Text("Maham One")
          .font(.largeTitle.bold())
        Text(AppServices.shared == nil ? "Not set up yet" : "Ready")
          .foregroundStyle(.secondary)
      }
      .padding(32)
      .glassEffect(.regular, in: .rect(cornerRadius: 28))
    }
  }
}
