// swift-tools-version: 6.0

import PackageDescription

let package = Package(
  name: "RemodexTextKit",
  platforms: [
    .macOS(.v15),
    .iOS(.v18),
    .tvOS(.v18),
    .watchOS(.v11),
    .visionOS(.v2),
  ],
  products: [
    .library(name: "RemodexTextKit", targets: ["RemodexTextKit"])
  ],
  dependencies: [
    .package(url: "https://github.com/pointfreeco/swift-concurrency-extras", from: "1.3.1"),
    .package(url: "https://github.com/pointfreeco/swift-snapshot-testing", from: "1.18.7"),
    .package(url: "https://github.com/gonzalezreal/swiftui-math", .upToNextMinor(from: "0.1.0")),
  ],
  targets: [
    .target(
      name: "RemodexTextKit",
      dependencies: [
        .product(name: "ConcurrencyExtras", package: "swift-concurrency-extras"),
        .product(name: "SwiftUIMath", package: "swiftui-math"),
      ],
      resources: [
        .process("Internal/Highlighter/Prism")
      ],
      swiftSettings: [
        .define("REMODEX_TEXT_KIT_ENABLE_LINKS", .when(platforms: [.macOS, .iOS, .watchOS, .visionOS])),
        .define("REMODEX_TEXT_KIT_ENABLE_TEXT_SELECTION", .when(platforms: [.macOS, .iOS, .visionOS])),
      ]
    ),
    .testTarget(
      name: "RemodexTextKitTests",
      dependencies: [
        "RemodexTextKit",
        .product(name: "SnapshotTesting", package: "swift-snapshot-testing"),
      ],
      exclude: [
        "Internal/TextInteraction/__Snapshots__",
        "StructuredText/__Snapshots__",
      ],
      resources: [.copy("Fixtures")],
      swiftSettings: [
        .define("REMODEX_TEXT_KIT_ENABLE_TEXT_SELECTION", .when(platforms: [.macOS, .iOS, .visionOS]))
      ]
    ),
  ]
)
