// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "AgentMeterDesktop",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "AgentMeterCore", targets: ["AgentMeterCore"]),
        .library(name: "AgentMeterIPC", targets: ["AgentMeterIPC"]),
    ],
    targets: [
        .target(name: "AgentMeterCore"),
        .target(name: "AgentMeterIPC", dependencies: ["AgentMeterCore"]),
        .testTarget(
            name: "AgentMeterCoreTests",
            dependencies: ["AgentMeterCore"],
            resources: [.copy("Fixtures")]
        ),
        .testTarget(
            name: "AgentMeterIPCTests",
            dependencies: ["AgentMeterIPC"]
        ),
    ]
)
