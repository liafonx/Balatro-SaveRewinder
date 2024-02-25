// swift-tools-version: 5.9
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "Balatro.antihypertensive",
    platforms: [
        .macOS(.v13)
    ],
    targets: [
        // Targets are the basic building blocks of a package, defining a module or a test suite.
        // Targets can depend on other targets in this package and products from dependencies.
        .target(
            name: "SaveManager",
            swiftSettings: [
                .unsafeFlags(["-enable-bare-slash-regex"])
            ]
        ),
        .executableTarget(
            name: "Executable",
            dependencies: [
                "SaveManager"
            ]
        ),
        .executableTarget(
            name: "GUI",
            dependencies: [
                "SaveManager"
            ]
        )
    ]
)
