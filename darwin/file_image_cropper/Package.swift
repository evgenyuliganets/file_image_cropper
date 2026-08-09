// swift-tools-version: 5.9

import PackageDescription

let package = Package(
  name: "file_image_cropper",
  platforms: [
    .iOS("13.0"),
    .macOS("10.15"),
  ],
  products: [
    .library(
      name: "file-image-cropper",
      targets: ["file_image_cropper"]
    ),
  ],
  dependencies: [
    .package(name: "FlutterFramework", path: "../FlutterFramework"),
  ],
  targets: [
    .target(
      name: "file_image_cropper_bridge",
      path: "Sources/file_image_cropper_bridge",
      publicHeadersPath: "include"
    ),
    .target(
      name: "file_image_cropper",
      dependencies: [
        .product(name: "FlutterFramework", package: "FlutterFramework"),
        "file_image_cropper_bridge",
      ],
      path: "Sources/file_image_cropper",
      linkerSettings: [
        .linkedFramework("CoreGraphics"),
        .linkedFramework("CoreImage"),
        .linkedFramework("ImageIO"),
      ]
    ),
  ]
)
