import AgentMeterCore
import Foundation

public struct WidgetWindowSelection: Equatable, Sendable {
    public let outer: ProviderWindow?
    public let inner: ProviderWindow?
    public let additional: [ProviderWindow]

    public init(outer: ProviderWindow?, inner: ProviderWindow?, additional: [ProviderWindow]) {
        self.outer = outer
        self.inner = inner
        self.additional = additional
    }
}

public enum WidgetWindowSelector {
    public static func historyEnabledKinds(from windows: [ProviderWindow]) -> [String] {
        let selection = select(from: windows)
        let prioritized = [selection.outer, selection.inner].compactMap { $0 } + selection.additional
        var seen = Set<String>()
        return Array(prioritized.compactMap { window in
            seen.insert(window.kind).inserted ? window.kind : nil
        }.prefix(WidgetSnapshot.maximumHistoryWindowCountPerProvider))
    }

    public static func select(
        from windows: [ProviderWindow],
        focusOuterKind: String? = nil,
        focusInnerKind: String? = nil
    ) -> WidgetWindowSelection {
        let indexed = Array(windows.enumerated())
        let explicitOuter = matchingIndex(for: focusOuterKind, in: indexed)
        let explicitInner = matchingIndex(for: focusInnerKind, in: indexed)
        let outerIndex: Int?
        let innerIndex: Int?

        if let explicitOuter {
            outerIndex = explicitOuter
            if let explicitInner, explicitInner != explicitOuter {
                innerIndex = explicitInner
            } else {
                innerIndex = preferredInnerIndex(in: indexed, excluding: explicitOuter)
            }
        } else if let explicitInner {
            innerIndex = explicitInner
            outerIndex = preferredOuterIndex(in: indexed, excluding: explicitInner)
        } else {
            outerIndex = preferredOuterIndex(in: indexed)
            innerIndex = preferredInnerIndex(in: indexed, excluding: outerIndex)
        }
        let selected = Set([outerIndex, innerIndex].compactMap { $0 })

        return WidgetWindowSelection(
            outer: outerIndex.map { windows[$0] },
            inner: innerIndex.map { windows[$0] },
            additional: indexed.compactMap { selected.contains($0.offset) ? nil : $0.element }
        )
    }

    private static func matchingIndex(
        for requestedKind: String?,
        in windows: [(offset: Int, element: ProviderWindow)],
        excluding excludedIndex: Int? = nil
    ) -> Int? {
        guard let requestedKind else { return nil }
        let requested = normalizedPhrase(requestedKind)
        guard requested.isEmpty == false else { return nil }
        return windows.first {
            $0.offset != excludedIndex && normalizedPhrase($0.element.kind) == requested
        }?.offset
    }

    private static func preferredOuterIndex(
        in windows: [(offset: Int, element: ProviderWindow)],
        excluding excludedIndex: Int? = nil
    ) -> Int? {
        let remaining = windows.filter { $0.offset != excludedIndex }
        return firstIndex(in: remaining, matching: isExactMonthlyOrBilling)
            ?? firstIndex(in: remaining, matching: isExactWeekly)
            ?? firstIndex(in: remaining) {
                isSessionLike($0) == false && isMonthlyBillingOrWeekly($0)
            }
            ?? firstIndex(in: remaining) { isSessionLike($0) == false }
            ?? remaining.first?.offset
    }

    private static func preferredInnerIndex(
        in windows: [(offset: Int, element: ProviderWindow)],
        excluding excludedIndex: Int?
    ) -> Int? {
        let remaining = windows.filter { $0.offset != excludedIndex }
        return firstIndex(in: remaining, matching: isExactSession)
            ?? firstIndex(in: remaining, matching: isDailyOrShort)
            ?? remaining.first?.offset
    }

    private static func firstIndex(
        in windows: [(offset: Int, element: ProviderWindow)],
        matching predicate: (ProviderWindow) -> Bool
    ) -> Int? {
        windows.first { predicate($0.element) }?.offset
    }

    private static func isExactMonthlyOrBilling(_ window: ProviderWindow) -> Bool {
        let exactPhrases = [normalizedPhrase(window.kind), normalizedPhrase(window.label)]
        return exactPhrases.contains { ["monthly", "month", "billing"].contains($0) }
    }

    private static func isMonthlyBillingOrWeekly(_ window: ProviderWindow) -> Bool {
        let tokens = normalizedTokens(window)
        return tokens.contains("monthly")
            || tokens.contains("month")
            || tokens.contains("billing")
            || tokens.contains("weekly")
            || tokens.contains("week")
    }

    private static func isExactWeekly(_ window: ProviderWindow) -> Bool {
        normalizedPhrase(window.kind) == "weekly" || normalizedPhrase(window.label) == "weekly"
    }

    private static func isSessionLike(_ window: ProviderWindow) -> Bool {
        normalizedTokens(window).contains("session")
    }

    private static func isExactSession(_ window: ProviderWindow) -> Bool {
        normalizedPhrase(window.kind) == "session" || normalizedPhrase(window.label) == "session"
    }

    private static func isDailyOrShort(_ window: ProviderWindow) -> Bool {
        let tokens = normalizedTokens(window)
        return tokens.contains("daily") || tokens.contains("day") || tokens.contains("short")
    }

    private static func normalizedTokens(_ window: ProviderWindow) -> Set<String> {
        Set(normalizedComponents(window.kind) + normalizedComponents(window.label))
    }

    private static func normalizedPhrase(_ value: String) -> String {
        normalizedComponents(value).joined(separator: "-")
    }

    private static func normalizedComponents(_ value: String) -> [String] {
        value.lowercased().components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { $0.isEmpty == false }
    }
}
