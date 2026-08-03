import SwiftUI

public struct ProviderMark: View {
    private let providerId: String
    private let name: String
    private let size: CGFloat

    public init(providerId: String, name: String, size: CGFloat = 38) {
        self.providerId = providerId
        self.name = name
        self.size = size
    }

    public var body: some View {
        let accent = ProviderPalette.accent(for: providerId)
        ZStack {
            Circle().fill(accent.opacity(0.14))
            mark(accent: accent)
                .padding(size * 0.22)
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }

    @ViewBuilder
    private func mark(accent: Color) -> some View {
        switch providerId.lowercased() {
        case "codex":
            Image(systemName: "hexagon")
                .font(.system(size: size * 0.46, weight: .medium))
                .foregroundStyle(accent)
                .overlay(
                    Image(systemName: "circle")
                        .font(.system(size: size * 0.21, weight: .medium))
                        .foregroundStyle(accent)
                )
        case "claude":
            Image(systemName: "asterisk")
                .font(.system(size: size * 0.50, weight: .bold))
                .foregroundStyle(accent)
        case "gemini":
            Image(systemName: "sparkle")
                .font(.system(size: size * 0.52, weight: .semibold))
                .foregroundStyle(accent)
        case "cursor":
            Image(systemName: "cube.transparent")
                .font(.system(size: size * 0.48, weight: .medium))
                .foregroundStyle(accent)
        default:
            Text(String(name.prefix(1)).uppercased())
                .font(.system(size: size * 0.42, weight: .bold, design: .rounded))
                .foregroundStyle(accent)
        }
    }
}
