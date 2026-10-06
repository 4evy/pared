// swift-tools-version: 6.2
import PackageDescription

let package = Package(
  name: "ParedApp",
  platforms: [.macOS("27.0")],
  products: [.executable(name: "ParedApp", targets: ["ParedApp"])],
  dependencies: [
    .package(name: "pared", path: ".."),
    .package(url: "https://github.com/sparkle-project/Sparkle", exact: "2.10.0"),
  ],
  targets: [
    .executableTarget(
      name: "ParedApp",
      dependencies: [
        .product(name: "ParedKit", package: "pared"),
        .product(name: "Sparkle", package: "Sparkle"),
      ],
      linkerSettings: [
        .unsafeFlags(["-Xlinker", "-rpath", "-Xlinker", "@executable_path/../Frameworks"])
      ])
  ]
)
