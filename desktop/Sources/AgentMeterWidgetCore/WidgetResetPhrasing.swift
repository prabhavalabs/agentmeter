import Foundation

/// Distance-classified reset copy from the v2 design language. The classes
/// let views choose a live-updating relative rendering inside 24 hours while
/// every class still has deterministic static text for dense layouts,
/// accessibility, and tests.
public enum WidgetResetPhrase: Equatable, Sendable {
    /// Under 24 hours away — long form "Resets in 2 hr 5 min".
    case relative(epoch: Int)
    /// Under 7 days away — long form "Resets Mon 6:00 PM".
    case weekdayTime(epoch: Int)
    /// 7 days or more away — long form "Resets Mon 12 Aug".
    case calendarDate(epoch: Int)
    /// The reset epoch has passed but fresh provider data has not arrived.
    case pending
    /// The provider reported no reset time.
    case unavailable
}

public enum WidgetResetPhrasing {
    public static let pendingText = "Refresh pending"
    public static let unavailableText = "Reset unavailable"

    public static func phrase(for state: WidgetResetState, nowEpoch: Int) -> WidgetResetPhrase {
        switch state {
        case .unavailable:
            return .unavailable
        case .pending:
            return .pending
        case let .scheduled(epoch):
            guard epoch > nowEpoch else { return .pending }
            let distance = epoch - nowEpoch
            if distance < 86_400 { return .relative(epoch: epoch) }
            if distance < 7 * 86_400 { return .weekdayTime(epoch: epoch) }
            return .calendarDate(epoch: epoch)
        }
    }

    public static func longText(
        _ phrase: WidgetResetPhrase,
        nowEpoch: Int,
        timeZone: TimeZone = .current,
        locale: Locale = .current
    ) -> String {
        switch phrase {
        case let .relative(epoch):
            return "Resets in \(relativeComponents(distance: epoch - nowEpoch))"
        case let .weekdayTime(epoch):
            return "Resets \(formatted("EEE h:mm a", epoch: epoch, timeZone: timeZone, locale: locale))"
        case let .calendarDate(epoch):
            return "Resets \(formatted("EEE d MMM", epoch: epoch, timeZone: timeZone, locale: locale))"
        case .pending:
            return pendingText
        case .unavailable:
            return unavailableText
        }
    }

    public static func compactText(
        _ phrase: WidgetResetPhrase,
        nowEpoch: Int,
        timeZone: TimeZone = .current,
        locale: Locale = .current
    ) -> String {
        switch phrase {
        case let .relative(epoch):
            return "⟳ \(compactComponents(distance: epoch - nowEpoch))"
        case let .weekdayTime(epoch):
            return "⟳ \(compactComponents(distance: epoch - nowEpoch))"
        case let .calendarDate(epoch):
            return "⟳ \(formatted("MMM d", epoch: epoch, timeZone: timeZone, locale: locale))"
        case .pending:
            return "⟳ …"
        case .unavailable:
            return "—"
        }
    }

    private static func relativeComponents(distance: Int) -> String {
        let clamped = max(0, distance)
        if clamped < 3_600 {
            return "\(max(1, clamped / 60)) min"
        }
        let hours = clamped / 3_600
        let minutes = (clamped % 3_600) / 60
        return minutes == 0 ? "\(hours) hr" : "\(hours) hr \(minutes) min"
    }

    private static func compactComponents(distance: Int) -> String {
        let clamped = max(0, distance)
        if clamped < 3_600 {
            return "\(max(1, clamped / 60))m"
        }
        if clamped < 86_400 {
            let hours = clamped / 3_600
            let minutes = (clamped % 3_600) / 60
            return minutes == 0 ? "\(hours)h" : "\(hours)h \(minutes)m"
        }
        let days = clamped / 86_400
        let hours = (clamped % 86_400) / 3_600
        return hours == 0 ? "\(days)d" : "\(days)d \(hours)h"
    }

    private static func formatted(
        _ format: String,
        epoch: Int,
        timeZone: TimeZone,
        locale: Locale
    ) -> String {
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.timeZone = timeZone
        formatter.setLocalizedDateFormatFromTemplate(format)
        // The template API reorders per locale; fall back to the literal
        // format when the locale is the deterministic POSIX one used in tests.
        if locale.identifier == "en_US_POSIX" {
            formatter.dateFormat = format
        }
        return formatter.string(from: Date(timeIntervalSince1970: TimeInterval(epoch)))
    }
}
