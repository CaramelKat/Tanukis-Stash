// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "Tanuki's Stash",
    platforms: [
        .iOS(.v17),
        .macOS(.v14),
    ],
    products: [
        .library(
            name: "The Tanuki's Stash",
            targets: ["Tanukis Stash"]
        ),
    ],
    dependencies: [
        .package(url: "https://github.com/elai950/AlertToast.git", from: "1.3.9"),
        .package(url: "https://github.com/Iaenhaall/AttributedText.git", from: "1.2.0"),
        .package(url: "https://github.com/kirualex/SwiftyGif.git", from: "5.4.4"),
        .package(url: "https://github.com/Jake-Short/swiftui-image-viewer.git", from: "2.3.1"),

    ],
    targets: [
        .target(
            name: "Tanukis Stash",
            dependencies: [
                .product(name: "ImageViewerRemote", package: "swiftui-image-viewer"),
                .product(name: "SwiftyGif", package: "SwiftyGif"),
                .product(name: "AttributedText", package: "AttributedText"),
                .product(name: "AlertToast", package: "AlertToast")
            ]
        ),
    ]
)
