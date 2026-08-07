import AgentMeterCore
import AppKit
import Foundation
import Observation
import UserNotifications

public struct PlannedNotification: Equatable, Sendable {
    public enum Kind: String, Sendable {
        case threshold
        case reset
        case connectionLost
    }

    public let identifier: String
    public let kind: Kind
    public let title: String
    public let body: String
    public let delaySeconds: TimeInterval?

    public init(
        identifier: String,
        kind: Kind,
        title: String,
        body: String,
        delaySeconds: TimeInterval? = nil
    ) {
        self.identifier = identifier
        self.kind = kind
        self.title = title
        self.body = body
        self.delaySeconds = delaySeconds
    }
}

public enum NotificationPlanner {
    public static func plans(
        eventId: String,
        previous: ControlState,
        current: ControlState
    ) -> [PlannedNotification] {
        var result: [PlannedNotification] = []
        let previousProviders = Dictionary(uniqueKeysWithValues: previous.providers.map { ($0.id, $0) })
        let thresholds = current.settings?.alertThresholds.sorted() ?? [70, 90]

        for provider in current.providers where provider.status == "ok" {
            guard let priorProvider = previousProviders[provider.id] else { continue }
            let priorWindows = Dictionary(uniqueKeysWithValues: priorProvider.windows.map { ($0.kind, $0) })
            for window in provider.windows {
                guard let percent = window.usedPercent,
                      let prior = priorWindows[window.kind],
                      let priorPercent = prior.usedPercent else { continue }

                if let crossed = thresholds.filter({ priorPercent < $0 && percent >= $0 }).max() {
                    result.append(
                        PlannedNotification(
                            identifier: "\(eventId):threshold:\(provider.id):\(window.kind):\(crossed)",
                            kind: .threshold,
                            title: "\(provider.name) usage reached \(percent)%",
                            body: "The \(window.label.lowercased()) allowance crossed your \(crossed)% alert level."
                        )
                    )
                }

                if percent < priorPercent,
                   window.resetAtEpoch != prior.resetAtEpoch {
                    result.append(
                        PlannedNotification(
                            identifier: "\(eventId):reset:\(provider.id):\(window.kind)",
                            kind: .reset,
                            title: "\(provider.name) allowance reset",
                            body: "The \(window.label.lowercased()) window is now at \(percent)% used."
                        )
                    )
                }
            }
        }

        if previous.connection.phase == .connected, current.connection.phase != .connected {
            result.append(
                PlannedNotification(
                    identifier: "\(eventId):connection-lost",
                    kind: .connectionLost,
                    title: "AgentMeter disconnected",
                    body: "The display has been unreachable for one minute. AgentMeter will keep trying.",
                    delaySeconds: 60
                )
            )
        }
        return result
    }
}

public enum NotificationPermissionState: Sendable {
    case notDetermined
    case denied
    case authorized
}

@MainActor
public protocol UserNotificationDelivering: AnyObject {
    func permissionState() async -> NotificationPermissionState
    func requestAuthorization() async throws -> Bool
    func add(_ plan: PlannedNotification) async throws
    func removePending(identifiers: [String])
}

@MainActor
@Observable
public final class UserNotificationController {
    public private(set) var isAuthorized = false
    public private(set) var isUpdating = false
    public private(set) var errorMessage: String?

    @ObservationIgnored private let delivery: any UserNotificationDelivering
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private var recentIds: [String]
    @ObservationIgnored private var pendingConnectionId: String?

    private static let recentIdsKey = "recentNotificationEventIds"
    private static let recentIdLimit = 64

    public init(
        defaults: UserDefaults = .standard,
        delivery: (any UserNotificationDelivering)? = nil
    ) {
        self.defaults = defaults
        self.delivery = delivery ?? SystemNotificationDelivery()
        recentIds = Array(
            (defaults.stringArray(forKey: Self.recentIdsKey) ?? []).suffix(Self.recentIdLimit)
        )
    }

    public func setEnabled(_ enabled: Bool) async -> Bool {
        errorMessage = nil
        guard enabled else {
            if let pendingConnectionId {
                delivery.removePending(identifiers: [pendingConnectionId])
                self.pendingConnectionId = nil
            }
            isAuthorized = false
            return true
        }
        isUpdating = true
        defer { isUpdating = false }
        switch await delivery.permissionState() {
        case .authorized:
            isAuthorized = true
            return true
        case .denied:
            isAuthorized = false
            errorMessage = Self.deniedMessage
            return false
        case .notDetermined:
            break
        }
        do {
            isAuthorized = try await delivery.requestAuthorization()
            if isAuthorized == false {
                errorMessage = Self.deniedMessage
            }
            return isAuthorized
        } catch {
            // A dev-signed bundle that Notification Center has not registered
            // yet fails here; point at the actionable fix instead of the
            // framework's wording.
            errorMessage = Self.deniedMessage
            isAuthorized = false
            return false
        }
    }

    public static let deniedMessage =
        "Allow notifications for AgentMeter in System Settings → Notifications."

    public static func openSystemNotificationSettings() {
        guard let url = URL(
            string: "x-apple.systempreferences:com.apple.Notifications-Settings.extension"
        ) else { return }
        NSWorkspace.shared.open(url)
    }

    public func process(
        eventId: String,
        previous: ControlState,
        current: ControlState,
        enabled: Bool
    ) {
        guard enabled, isAuthorized else { return }
        if current.connection.phase == .connected, let pendingConnectionId {
            delivery.removePending(identifiers: [pendingConnectionId])
            self.pendingConnectionId = nil
        }
        for plan in NotificationPlanner.plans(
            eventId: eventId,
            previous: previous,
            current: current
        ) where recentIds.contains(plan.identifier) == false {
            remember(plan.identifier)
            if plan.kind == .connectionLost { pendingConnectionId = plan.identifier }
            Task {
                do {
                    try await delivery.add(plan)
                } catch {
                    errorMessage = error.localizedDescription
                }
            }
        }
    }

    private func remember(_ identifier: String) {
        recentIds.append(identifier)
        if recentIds.count > Self.recentIdLimit {
            recentIds.removeFirst(recentIds.count - Self.recentIdLimit)
        }
        defaults.set(recentIds, forKey: Self.recentIdsKey)
    }
}

@MainActor
private final class SystemNotificationDelivery: NSObject, UserNotificationDelivering {
    private let center = UNUserNotificationCenter.current()
    private let notificationDelegate = AgentMeterNotificationDelegate()

    override init() {
        super.init()
        center.delegate = notificationDelegate
    }

    func permissionState() async -> NotificationPermissionState {
        switch await center.notificationSettings().authorizationStatus {
        case .authorized, .provisional: .authorized
        case .denied: .denied
        case .notDetermined: .notDetermined
        @unknown default: .notDetermined
        }
    }

    func requestAuthorization() async throws -> Bool {
        try await center.requestAuthorization(options: [.alert, .sound])
    }

    func add(_ plan: PlannedNotification) async throws {
        let content = UNMutableNotificationContent()
        content.title = plan.title
        content.body = plan.body
        content.sound = .default
        let trigger = plan.delaySeconds.map {
            UNTimeIntervalNotificationTrigger(timeInterval: $0, repeats: false)
        }
        try await center.add(
            UNNotificationRequest(identifier: plan.identifier, content: content, trigger: trigger)
        )
    }

    func removePending(identifiers: [String]) {
        center.removePendingNotificationRequests(withIdentifiers: identifiers)
    }
}

private final class AgentMeterNotificationDelegate: NSObject, UNUserNotificationCenterDelegate,
    @unchecked Sendable
{
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound])
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        DispatchQueue.main.async {
            NSApplication.shared.activate(ignoringOtherApps: true)
            NSApplication.shared.windows
                .first(where: { $0.title.contains("AgentMeter") })?
                .makeKeyAndOrderFront(nil)
        }
        completionHandler()
    }
}
