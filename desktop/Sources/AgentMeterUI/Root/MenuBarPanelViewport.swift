import SwiftUI

/// Gives `MenuBarExtra` a stable intrinsic size while allowing tall content to scroll.
public struct MenuBarPanelViewport<Content: View>: View {
    private let content: Content

    public init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    public var body: some View {
        MenuBarScrollView {
            content
        }
        .frame(width: 320, height: 700)
    }
}
