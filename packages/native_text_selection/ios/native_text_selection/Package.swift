// swift-tools-version: 5.9
import PackageDescription

let package = Package(
  name: "native_text_selection",
  platforms: [.iOS(.v15)],
  products: [
    .library(name: "native-text-selection", targets: ["native_text_selection"])
  ],
  dependencies: [
    .package(name: "FlutterFramework", path: "../FlutterFramework")
  ],
  targets: [
    .target(
      name: "native_text_selection",
      dependencies: [.product(name: "FlutterFramework", package: "FlutterFramework")]
    ),
    .testTarget(
      name: "native_text_selectionTests",
      dependencies: ["native_text_selection"]
    )
  ]
)
