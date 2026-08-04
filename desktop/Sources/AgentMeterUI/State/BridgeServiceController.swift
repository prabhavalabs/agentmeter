import AppKit
import CryptoKit
import Darwin
import Foundation
import Observation
import OSLog
import ServiceManagement

public enum BridgeServiceState: Equatable, Sendable {
    case idle
    case preparing
    case registering
    case waitingForBridge
    case ready
    case external
    case needsApproval
    case unavailable
    case failed(String)

    public var title: String {
        switch self {
        case .idle: "Not started"
        case .preparing: "Preparing"
        case .registering: "Registering"
        case .waitingForBridge: "Starting"
        case .ready: "Running"
        case .external: "Development bridge"
        case .needsApproval: "Approval required"
        case .unavailable: "Bundle required"
        case .failed: "Needs attention"
        }
    }

    public var isUsable: Bool {
        switch self {
        case .waitingForBridge, .ready, .external: true
        default: false
        }
    }

    public var detail: String? {
        if case let .failed(message) = self { return message }
        return nil
    }
}

public enum BridgeDistributionMode: Equatable, Sendable {
    case managed
    case community

    public static func resolve(plistValue: String?) -> BridgeDistributionMode {
        plistValue == "community" ? .community : .managed
    }
}

@MainActor
@Observable
public final class BridgeServiceController {
    public static let plistName = "com.prabhavalabs.agentmeter.bridge.plist"
    public static let legacyLabel = "com.prabhavalabs.agentmeter"

    public private(set) var state: BridgeServiceState = .idle
    public private(set) var isUpdating = false
    public private(set) var hasBundledBridge: Bool

    public var isCommunityBuild: Bool {
        distributionMode == .community
    }

    private let service: SMAppService
    private let bundle: Bundle
    private let fileManager: FileManager
    private let externalMode: Bool
    private let defaults: UserDefaults
    private let distributionMode: BridgeDistributionMode
    private let ipcPath: String
    private var hasStarted = false
    private var communityProcess: Process?
    private let logger = Logger(
        subsystem: "com.prabhavalabs.agentmeter.desktop",
        category: "BridgeService"
    )

    public init(
        bundle: Bundle = .main,
        fileManager: FileManager = .default,
        defaults: UserDefaults = .standard,
        externalMode: Bool = false,
        distributionMode: BridgeDistributionMode? = nil,
        ipcPath: String? = nil
    ) {
        self.bundle = bundle
        self.fileManager = fileManager
        self.externalMode = externalMode
        self.defaults = defaults
        self.distributionMode = distributionMode ?? BridgeDistributionMode.resolve(
            plistValue: bundle.object(forInfoDictionaryKey: "AgentMeterDistributionMode") as? String
        )
        self.ipcPath = ipcPath ?? URL(
            fileURLWithPath: NSTemporaryDirectory(),
            isDirectory: true
        )
        .appendingPathComponent("agentmeter-\(getuid())", isDirectory: true)
        .appendingPathComponent("bridge.sock", isDirectory: false)
        .path
        service = SMAppService.agent(plistName: Self.plistName)
        hasBundledBridge = bundle.resourceURL?
            .appendingPathComponent("AgentMeterBridge/AgentMeterBridge")
            .isFileURL == true
            && fileManager.isExecutableFile(
                atPath: bundle.resourceURL?
                    .appendingPathComponent("AgentMeterBridge/AgentMeterBridge").path ?? ""
            )
        if externalMode {
            state = .external
        } else if hasBundledBridge == false {
            state = .unavailable
        }
    }

    public func start() async {
        guard hasStarted == false else { return }
        hasStarted = true
        if externalMode {
            state = .external
            return
        }
        guard hasBundledBridge else {
            state = .unavailable
            return
        }

        isUpdating = true
        defer { isUpdating = false }
        do {
            state = .preparing
            let configuration = try prepareConfiguration()
            if distributionMode == .community {
                if service.status != .notRegistered, service.status != .notFound {
                    try? await service.unregister()
                }
                stopLegacyServiceIfPresent()
                try startCommunityBridge(configuration: configuration)
                state = .waitingForBridge
                return
            }
            state = .registering
            var shouldRegister = service.status == .notRegistered || service.status == .notFound
            if service.status == .enabled,
               let digest = currentHelperDigest,
               defaults.string(forKey: "registeredBridgeDigest") != digest {
                try await service.unregister()
                shouldRegister = true
            }
            if shouldRegister {
                try service.register()
            }
            let status = await settledStatus()
            if status == .requiresApproval {
                state = .needsApproval
                hasStarted = false
                return
            }
            guard status == .enabled else {
                state = .failed("The background bridge is not enabled in Login Items.")
                hasStarted = false
                return
            }
            stopLegacyServiceIfPresent()
            state = .waitingForBridge
        } catch {
            logger.error("Bridge service registration failed: \(error.localizedDescription, privacy: .public)")
            state = .failed(error.localizedDescription)
            hasStarted = false
        }
    }

    public func retry() async {
        hasStarted = false
        await start()
    }

    public func confirmBridgeReady() {
        guard state == .waitingForBridge || state == .external else { return }
        state = externalMode ? .external : .ready
        if let digest = currentHelperDigest {
            defaults.set(digest, forKey: "registeredBridgeDigest")
        }
        archiveLegacyLaunchAgent()
    }

    public func stop() async {
        guard externalMode == false, hasBundledBridge else { return }
        isUpdating = true
        defer { isUpdating = false }
        if distributionMode == .community {
            let process = communityProcess
            communityProcess = nil
            if process?.isRunning == true {
                process?.terminate()
            }
            state = .idle
            hasStarted = false
            return
        }
        do {
            if service.status != .notRegistered {
                try await service.unregister()
            }
            state = .idle
            hasStarted = false
        } catch {
            logger.error("Bridge service removal failed: \(error.localizedDescription, privacy: .public)")
            state = .failed(error.localizedDescription)
        }
    }

    public func openLoginItemsSettings() {
        guard let url = URL(
            string: "x-apple.systempreferences:com.apple.LoginItems-Settings.extension"
        ) else { return }
        NSWorkspace.shared.open(url)
    }

    public nonisolated static func communityBridgeArguments(
        configurationPath: String,
        ipcPath: String,
        parentPID: pid_t
    ) -> [String] {
        [
            "run",
            "--config", configurationPath,
            "--ipc-path", ipcPath,
            "--parent-pid", String(parentPID),
        ]
    }

    private func prepareConfiguration() throws -> URL {
        let support = try fileManager.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        ).appendingPathComponent("AgentMeter", isDirectory: true)
        try fileManager.createDirectory(
            at: support,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        let destination = support.appendingPathComponent("config.toml")
        guard fileManager.fileExists(atPath: destination.path) == false else {
            return destination
        }

        let legacy = fileManager.homeDirectoryForCurrentUser
            .appendingPathComponent(".config/AgentMeter/config.toml")
        if fileManager.fileExists(atPath: legacy.path) {
            try fileManager.copyItem(at: legacy, to: destination)
            return destination
        }
        guard let template = bundle.url(forResource: "config.example", withExtension: "toml") else {
            throw CocoaError(.fileNoSuchFile)
        }
        try fileManager.copyItem(at: template, to: destination)
        return destination
    }

    private func startCommunityBridge(configuration: URL) throws {
        if communityProcess?.isRunning == true { return }
        guard let executable = bundle.resourceURL?
            .appendingPathComponent("AgentMeterBridge/AgentMeterBridge") else {
            throw CocoaError(.fileNoSuchFile)
        }

        let process = Process()
        process.executableURL = executable
        process.arguments = Self.communityBridgeArguments(
            configurationPath: configuration.path,
            ipcPath: ipcPath,
            parentPID: getpid()
        )
        var environment = ProcessInfo.processInfo.environment
        environment["PATH"] = "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin"
        environment["PYTHONUNBUFFERED"] = "1"
        process.environment = environment
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        process.terminationHandler = { [weak self, weak process] _ in
            Task { @MainActor in
                guard let self, let process, self.communityProcess === process else { return }
                self.communityProcess = nil
                self.hasStarted = false
                self.state = .failed("The bundled bridge stopped unexpectedly.")
            }
        }
        try process.run()
        communityProcess = process
    }

    private func settledStatus() async -> SMAppService.Status {
        for _ in 0 ..< 20 {
            let status = service.status
            if status != .notRegistered, status != .notFound { return status }
            try? await Task.sleep(for: .milliseconds(100))
        }
        return service.status
    }

    private func stopLegacyServiceIfPresent() {
        let legacyPlist = legacyLaunchAgentURL
        guard fileManager.fileExists(atPath: legacyPlist.path) else { return }
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        task.arguments = ["bootout", "gui/\(getuid())/\(Self.legacyLabel)"]
        task.standardOutput = FileHandle.nullDevice
        task.standardError = FileHandle.nullDevice
        try? task.run()
        task.waitUntilExit()
    }

    private func archiveLegacyLaunchAgent() {
        guard externalMode == false else { return }
        let legacy = legacyLaunchAgentURL
        guard fileManager.fileExists(atPath: legacy.path) else { return }
        do {
            let support = try fileManager.url(
                for: .applicationSupportDirectory,
                in: .userDomainMask,
                appropriateFor: nil,
                create: true
            ).appendingPathComponent("AgentMeter/Migration", isDirectory: true)
            try fileManager.createDirectory(at: support, withIntermediateDirectories: true)
            let backup = support.appendingPathComponent("\(Self.legacyLabel).plist")
            if fileManager.fileExists(atPath: backup.path) {
                try fileManager.removeItem(at: backup)
            }
            try fileManager.moveItem(at: legacy, to: backup)
        } catch {
            // A retained legacy plist is harmless once its job is booted out.
        }
    }

    private var legacyLaunchAgentURL: URL {
        fileManager.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/LaunchAgents/\(Self.legacyLabel).plist")
    }

    private var currentHelperDigest: String? {
        guard let url = bundle.resourceURL?
            .appendingPathComponent("AgentMeterBridge/AgentMeterBridge"),
            let data = try? Data(contentsOf: url, options: .mappedIfSafe) else { return nil }
        return SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}
