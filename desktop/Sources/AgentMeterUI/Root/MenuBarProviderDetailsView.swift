import AgentMeterCore
import SwiftUI

struct MenuBarProviderDetailsView: View {
    let provider: ProviderSummary

    var body: some View {
        let details = MenuProviderDetails(provider: provider)
        VStack(alignment: .leading, spacing: 10) {
            statusRow

            if let session = details.sessionWindow {
                detailSection("Current session") {
                    MenuBarUsageWindowView(
                        window: session,
                        accent: accent,
                        nowEpoch: nowEpoch
                    )
                }
            }

            if let cycle = details.cycleWindow {
                detailSection("Overall cycle") {
                    MenuBarUsageWindowView(
                        window: cycle,
                        accent: accent,
                        nowEpoch: nowEpoch
                    )
                }
            }

            if details.modelWindows.isEmpty == false {
                detailSection("Usage by model") {
                    VStack(spacing: 7) {
                        ForEach(details.modelWindows) { window in
                            MenuBarUsageWindowView(
                                window: window,
                                accent: accent,
                                nowEpoch: nowEpoch
                            )
                        }
                    }
                }
            }

            if provider.windows.isEmpty {
                Label("Detailed usage is not reported", systemImage: "minus.circle")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 10)
        .padding(.vertical, 10)
        .accessibilityElement(children: .contain)
    }

    private var statusRow: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(statusTint)
                .frame(width: 6, height: 6)
            Text(statusText)
                .foregroundStyle(statusTint)
            Spacer(minLength: 8)
            Text(UsageFormatting.updatedAge(
                updatedAtEpoch: provider.updatedAtEpoch,
                nowEpoch: nowEpoch
            ))
            .foregroundStyle(.tertiary)
        }
        .font(.caption2.weight(.semibold))
    }

    private func detailSection<Content: View>(
        _ title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title.uppercased())
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(.tertiary)
                .tracking(0.45)
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var accent: Color { ProviderPalette.accent(for: provider.id) }
    private var nowEpoch: Int { Int(Date().timeIntervalSince1970) }

    private var statusText: String {
        switch provider.status {
        case "ok": "Live"
        case "stale": "Last known value"
        case "unavailable": "Unavailable"
        default: provider.status.capitalized
        }
    }

    private var statusTint: Color {
        switch provider.status {
        case "ok": AgentMeterTheme.success
        case "stale": AgentMeterTheme.warning
        default: AgentMeterTheme.secondaryText
        }
    }
}

private struct MenuBarUsageWindowView: View {
    let window: ProviderWindow
    let accent: Color
    let nowEpoch: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(window.label)
                    .font(.caption.weight(.medium))
                    .lineLimit(1)
                Spacer(minLength: 4)
                Text(UsageFormatting.percentage(window.usedPercent))
                    .font(.caption.bold().monospacedDigit())
                    .foregroundStyle(window.usedPercent == nil ? .secondary : .primary)
            }

            if let percent = window.usedPercent {
                ProgressView(value: Double(percent), total: 100)
                    .controlSize(.mini)
                    .tint(accent)
            } else {
                Text("Provider did not report a value")
                    .font(.system(size: 9.5))
                    .foregroundStyle(.secondary)
            }

            Label(
                UsageFormatting.resetCountdown(
                    resetAtEpoch: window.resetAtEpoch,
                    nowEpoch: nowEpoch
                ),
                systemImage: "clock"
            )
            .font(.system(size: 9.5))
            .foregroundStyle(.secondary)
        }
        .padding(8)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.primary.opacity(0.035))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(Color.primary.opacity(0.055), lineWidth: 0.5)
        )
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
