// swift-tools-version: 6.2
import PackageDescription

#if !compiler(>=6.2.4)
  #error("pared requires Swift 6.2.4 or newer. Build with nix build or enter nix develop.")
#endif

let package = Package(
  name: "pared",
  platforms: [.macOS("27.0")],
  products: [.executable(name: "pared", targets: ["Pared"])],
  dependencies: [
    .package(url: "https://github.com/tuist/Noora", exact: "0.57.3")
  ],
  targets: [
    .target(name: "AssetBridge", cSettings: [.unsafeFlags(["-fobjc-arc"])]),
    // Group sources by subsystem; Swift requires unique basenames in a target
    .executableTarget(
      name: "Pared",
      dependencies: ["AssetBridge", .product(name: "Noora", package: "Noora")],
      resources: [.process("Resources")]),
  ]
)
