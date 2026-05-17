// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "CalendarBlocker",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "CalendarBlocker",
            path: "Sources/CalendarBlocker"
        )
    ]
)
