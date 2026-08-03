import SwiftUI

struct MenuBarRowLabel<Trailing: View>: View {
    private let title: String
    private let symbol: String
    private let tint: Color
    private let isDestructive: Bool
    private let trailing: Trailing
    @State private var isHovered = false

    init(
        title: String,
        symbol: String,
        tint: Color,
        isDestructive: Bool = false,
        trailingSymbol: String? = nil
    ) where Trailing == AnyView {
        self.title = title
        self.symbol = symbol
        self.tint = tint
        self.isDestructive = isDestructive
        trailing = AnyView(
            trailingSymbol.map {
                Image(systemName: $0)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
        )
    }

    init(
        title: String,
        symbol: String,
        tint: Color,
        isDestructive: Bool = false,
        @ViewBuilder trailing: () -> Trailing
    ) {
        self.title = title
        self.symbol = symbol
        self.tint = tint
        self.isDestructive = isDestructive
        self.trailing = trailing()
    }

    var body: some View {
        HStack(spacing: 10) {
            MenuBarIconBadge(symbol: symbol, tint: tint)
            Text(title)
                .font(.body.weight(.medium))
                .foregroundStyle(isDestructive ? tint : .primary)
                .lineLimit(1)
            Spacer(minLength: 12)
            trailing
        }
        .padding(.horizontal, 8)
        .frame(height: 38)
        .contentShape(Rectangle())
        .background(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(isHovered ? Color.primary.opacity(0.075) : .clear)
        )
        .onHover { isHovered = $0 }
    }
}

struct MenuBarToggleRow: View {
    let title: String
    let symbol: String
    let tint: Color
    @Binding var isOn: Bool
    @State private var isHovered = false

    var body: some View {
        Toggle(isOn: $isOn) {
            HStack(spacing: 10) {
                MenuBarIconBadge(symbol: symbol, tint: tint)
                Text(title)
                    .font(.body.weight(.medium))
                Spacer(minLength: 12)
            }
        }
        .toggleStyle(.switch)
        .controlSize(.small)
        .padding(.horizontal, 8)
        .frame(height: 38)
        .contentShape(Rectangle())
        .background(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(isHovered ? Color.primary.opacity(0.075) : .clear)
        )
        .onHover { isHovered = $0 }
    }
}

private struct MenuBarIconBadge: View {
    let symbol: String
    let tint: Color

    var body: some View {
        ZStack {
            Circle().fill(tint.opacity(0.14))
            Image(systemName: symbol)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(tint)
                .symbolRenderingMode(.hierarchical)
        }
        .frame(width: 28, height: 28)
        .accessibilityHidden(true)
    }
}

extension View {
    func menuBarGroup() -> some View {
        background(
            RoundedRectangle(cornerRadius: 13, style: .continuous)
                .fill(AgentMeterTheme.surface.opacity(0.72))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 13, style: .continuous)
                .stroke(AgentMeterTheme.border.opacity(0.55), lineWidth: 1)
        )
    }
}
