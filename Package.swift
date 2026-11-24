// swift-tools-version: 6.0
import PackageDescription

let package = Package(
  name: "eighty",
  // Keep in step with MIN_MACOS in scripts/release.env.
  platforms: [.macOS("27.0")],
  targets: [
    .target(
      name: "CSystem",
      linkerSettings: [.linkedFramework("IOKit"), .linkedFramework("Foundation")]
    ),
    .target(name: "EightyCore"),
    .target(name: "EightyKit", dependencies: ["CSystem", "EightyCore"]),
    .executableTarget(name: "eighty", dependencies: ["CSystem", "EightyCore", "EightyKit"]),
    .executableTarget(name: "EightyBar", dependencies: ["EightyCore", "EightyKit"]),
    .testTarget(name: "EightyCoreTests", dependencies: ["EightyCore"]),
  ]
)
