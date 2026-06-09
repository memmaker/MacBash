// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "BashTwoWindows",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "BashTwoWindows", targets: ["BashTwoWindows"])
    ],
    targets: [
        .executableTarget(
            name: "BashTwoWindows",
            path: "Sources/BashTwoWindows"
        )
    ]
)
