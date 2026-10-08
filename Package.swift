// swift-tools-version: 6.2
import PackageDescription

#if !compiler(>=6.2.4)
  #error("pared requires Swift 6.2.4 or newer. Build with nix build or enter nix develop.")
#endif

let package = Package(
  name: "pared",
  platforms: [.macOS("27.0")],
  products: [
    .executable(name: "pared", targets: ["ParedCLI"]),
    .library(name: "ParedKit", targets: ["Pared"]),
  ],
  dependencies: [
    .package(url: "https://github.com/tuist/Noora", exact: "0.57.3"),
    .package(url: "https://github.com/apple/swift-argument-parser", exact: "1.8.2"),
    .package(url: "https://github.com/swiftlang/swift-subprocess", exact: "1.0.0"),
  ],
  targets: [
    .target(name: "AssetBridge"),
    // Group sources by subsystem; Swift requires unique basenames in a target
    .target(
      name: "Pared",
      dependencies: [
        "AssetBridge",
        .product(name: "Noora", package: "Noora"),
        .product(name: "ArgumentParser", package: "swift-argument-parser"),
        .product(name: "Subprocess", package: "swift-subprocess"),
      ],
      resources: [.process("Resources")]),
    .executableTarget(name: "ParedCLI", dependencies: ["Pared"]),
  ]
)
