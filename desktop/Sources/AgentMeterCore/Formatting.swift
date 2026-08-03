import Foundation

public enum UsageFormatting {
    public static func percentage(_ value: Int?) -> String {
        guard let value, (0...100).contains(value) else { return "Unavailable" }
        return "\(value)%"
    }

    public static func resetCountdown(resetAtEpoch: Int?, nowEpoch: Int) -> String {
        guard let resetAtEpoch else { return "Reset unavailable" }
        let remaining = resetAtEpoch - nowEpoch
        guard remaining > 0 else { return "Reset due" }
        if remaining < 60 { return "Resets in <1m" }
        let minutes = remaining / 60
        if minutes < 60 { return "Resets in \(minutes)m" }
        let hours = minutes / 60
        let leftoverMinutes = minutes % 60
        if hours < 24 { return "Resets in \(hours)h \(leftoverMinutes)m" }
        let days = hours / 24
        let leftoverHours = hours % 24
        return "Resets in \(days)d \(leftoverHours)h"
    }

    public static func updatedAge(updatedAtEpoch: Int?, nowEpoch: Int) -> String {
        guard let updatedAtEpoch else { return "Update unavailable" }
        let age = max(0, nowEpoch - updatedAtEpoch)
        if age < 60 { return "Updated now" }
        let minutes = age / 60
        if minutes < 60 { return "Updated \(minutes)m ago" }
        let hours = minutes / 60
        if hours < 24 { return "Updated \(hours)h ago" }
        return "Updated \(hours / 24)d ago"
    }
}

public enum TelemetryFormatting {
    public static func powerSource(_ value: String?) -> String {
        switch value {
        case "usb": "USB"
        case "battery": "Battery"
        default: "Unavailable"
        }
    }

    public static func battery(present: Bool?, percent: Int?) -> String {
        if present == false { return "Not installed" }
        guard present == true else { return "Unavailable" }
        return UsageFormatting.percentage(percent)
    }

    public static func millivolts(_ value: Int?) -> String {
        guard let value, value >= 0 else { return "Unavailable" }
        return String(format: "%.2f V", Double(value) / 1_000)
    }

    public static func uptime(_ seconds: Int?) -> String {
        guard let seconds, seconds >= 0 else { return "Unavailable" }
        let hours = seconds / 3_600
        let minutes = seconds % 3_600 / 60
        return "\(hours)h \(minutes)m"
    }
}
