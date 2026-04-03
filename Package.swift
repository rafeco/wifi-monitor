// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "WiFiMonitor",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "WiFiMonitor",
            path: "Sources/WiFiMonitor"
        )
    ]
)
