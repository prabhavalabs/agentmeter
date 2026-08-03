// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "AgentMeterDesktop",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "AgentMeter", targets: ["AgentMeterApp"]),
        .library(name: "AgentMeterCore", targets: ["AgentMeterCore"]),
        .library(name: "AgentMeterIPC", targets: ["AgentMeterIPC"]),
        .library(name: "AgentMeterUI", targets: ["AgentMeterUI"]),
    ],
    targets: [
        .target(name: "AgentMeterCore"),
        .target(name: "AgentMeterIPC", dependencies: ["AgentMeterCore"]),
        .target(
            name: "AgentMeterUI",
            dependencies: ["AgentMeterCore", "AgentMeterIPC"]
        ),
        .executableTarget(
            name: "AgentMeterApp",
            dependencies: ["AgentMeterCore", "AgentMeterIPC", "AgentMeterUI"]
        ),
        .testTarget(
            name: "AgentMeterCoreTests",
            dependencies: ["AgentMeterCore"],
            resources: [.copy("Fixtures")]
        ),
        .testTarget(
            name: "AgentMeterIPCTests",
            dependencies: ["AgentMeterIPC"]
        ),
        .testTarget(
            name: "AgentMeterUITests",
            dependencies: ["AgentMeterCore", "AgentMeterIPC", "AgentMeterUI"]
        ),
    ]
)
