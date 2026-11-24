// swift-tools-version: 6.2
import PackageDescription

/// What the Maham One iPhone app knows without a screen: signing in, the
/// database client, and the data of its two departments (Maham One and Maham
/// Tasks). It has no UIKit or SwiftUI in it, so it builds and is tested on
/// Linux too (`swift test` in this folder).
let package = Package(
  name: "MahamKit",
  defaultLocalization: "en",
  platforms: [.iOS(.v26), .macOS(.v15)],
  products: [
    .library(name: "MahamKit", targets: ["MahamKit"])
  ],
  targets: [
    .target(name: "MahamKit"),
    .testTarget(name: "MahamKitTests", dependencies: ["MahamKit"]),
  ]
)
