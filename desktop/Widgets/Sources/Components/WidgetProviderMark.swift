import SwiftUI

struct WidgetProviderMark: View {
    let providerID: String
    let name: String
    let accent: Color
    var size: CGFloat = 30

    var body: some View {
        ZStack {
            Circle()
                .fill(accent.opacity(0.14))
            glyph
                .foregroundStyle(accent)
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }

    @ViewBuilder
    private var glyph: some View {
        switch providerID.lowercased() {
        case "codex":
            Image(systemName: "hexagon")
                .font(.system(size: size * 0.5, weight: .semibold))
                .overlay {
                    Circle()
                        .stroke(lineWidth: max(1, size * 0.045))
                        .frame(width: size * 0.2, height: size * 0.2)
                }
        case "claude":
            Image(systemName: "asterisk")
                .font(.system(size: size * 0.54, weight: .bold))
        case "gemini":
            Image(systemName: "sparkle")
                .font(.system(size: size * 0.56, weight: .semibold))
        case "cursor":
            Image(systemName: "cube.transparent")
                .font(.system(size: size * 0.5, weight: .medium))
        default:
            Text(String(name.prefix(1)).uppercased())
                .font(.system(size: size * 0.42, weight: .bold, design: .rounded))
        }
    }
}
