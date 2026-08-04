import AppKit
import SwiftUI

/// A trackpad-scrollable menu viewport that never reserves or draws a scrollbar.
@MainActor
struct MenuBarScrollView<Content: View>: NSViewRepresentable {
    private let content: Content
    private let viewportWidth: CGFloat
    private let viewportHeight: CGFloat

    init(
        width: CGFloat = 320,
        height: CGFloat = 700,
        @ViewBuilder content: () -> Content
    ) {
        viewportWidth = width
        viewportHeight = height
        self.content = content()
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder
        scrollView.hasVerticalScroller = false
        scrollView.hasHorizontalScroller = false
        scrollView.verticalScroller = nil
        scrollView.horizontalScroller = nil
        scrollView.autohidesScrollers = true
        scrollView.horizontalScrollElasticity = .none
        scrollView.automaticallyAdjustsContentInsets = false
        scrollView.contentInsets = NSEdgeInsets()
        scrollView.documentView = context.coordinator.hostingView
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        context.coordinator.update(
            content: content,
            width: viewportWidth,
            minimumHeight: viewportHeight
        )
    }

    @MainActor
    final class Coordinator {
        let hostingView = NSHostingView(rootView: AnyView(EmptyView()))

        func update(content: Content, width: CGFloat, minimumHeight: CGFloat) {
            hostingView.rootView = AnyView(
                content.frame(width: width, alignment: .topLeading)
            )
            hostingView.frame = NSRect(x: 0, y: 0, width: width, height: minimumHeight)
            hostingView.layoutSubtreeIfNeeded()
            hostingView.frame.size.height = max(minimumHeight, hostingView.fittingSize.height)
        }
    }
}
