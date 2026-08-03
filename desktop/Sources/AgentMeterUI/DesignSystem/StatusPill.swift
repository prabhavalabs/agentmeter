import SwiftUI

public struct StatusPill: View {
    private let text: String
    private let symbol: String
    private let tint: Color

    public init(_ text: String, symbol: String, tint: Color) {
        self.text = text
        self.symbol = symbol
        self.tint = tint
    }

    public var body: some View {
        Label(text, systemImage: symbol)
            .font(.caption.weight(.semibold))
            .foregroundStyle(tint)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(tint.opacity(0.12), in: Capsule())
            .overlay(Capsule().stroke(tint.opacity(0.35), lineWidth: 1))
            .accessibilityLabel(text)
    }
}
