// swift-tools-version: 5.10
import PackageDescription

#if !compiler(>=5.10.1)
  #error("pared requires Swift 5.10.1 or newer. Build with nix build or enter nix develop.")
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
