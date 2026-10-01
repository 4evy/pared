// swift-tools-version: 6.2
import PackageDescription

#if !compiler(>=6.2.4)
  #error("pared requires Swift 6.2.4 or newer. Build with nix build or enter nix develop.")
#endif

let package = Package(
  name: "pared",
  platforms: [.macOS(.v14)],
  products: [.executable(name: "pared", targets: ["Pared"])],
  targets: [
    .target(name: "AssetBridge", cSettings: [.unsafeFlags(["-fobjc-arc"])]),
    .executableTarget(
      name: "Pared", dependencies: ["AssetBridge"], resources: [.process("Resources")]),
  ]
)
