import AgentMeterCore
import AppKit
import SwiftUI
import Testing
@testable import AgentMeterUI

@MainActor
@Test func menuBarViewportAdvertisesAUsableIntrinsicSize() {
    let hostingView = NSHostingView(
        rootView: MenuBarPanelViewport {
            Text("AgentMeter")
        }
    )

    hostingView.layoutSubtreeIfNeeded()

    #expect(hostingView.fittingSize.width >= 300)
    #expect(hostingView.fittingSize.height >= 600)
}

@MainActor
@Test func menuBarViewportDoesNotInstallAVisibleScroller() throws {
    let hostingView = NSHostingView(
        rootView: MenuBarScrollView {
            VStack {
                ForEach(0 ..< 100) { index in
                    Text("Row \(index)")
                }
            }
        }
        .frame(width: 320, height: 700)
    )
    hostingView.frame = NSRect(x: 0, y: 0, width: 320, height: 700)
    hostingView.layoutSubtreeIfNeeded()

    let scrollView = try #require(hostingView.descendants(of: NSScrollView.self).first)
    #expect(scrollView.hasVerticalScroller == false)
    #expect(scrollView.verticalScroller == nil)
}

@MainActor
@Test func expandedUsageProgressUsesTheAvailableRowWidth() throws {
    let provider = ProviderSummary(
        id: "codex",
        name: "Codex",
        status: "ok",
        windows: [
            ProviderWindow(
                kind: "weekly",
                label: "Weekly",
                usedPercent: 43,
                resetAtEpoch: 2_000
            ),
        ]
    )
    let hostingView = NSHostingView(
        rootView: MenuBarProviderDetailsView(provider: provider)
            .frame(width: 300)
    )
    hostingView.frame = NSRect(x: 0, y: 0, width: 300, height: 400)
    hostingView.layoutSubtreeIfNeeded()

    let progress = try #require(hostingView.descendants(of: NSProgressIndicator.self).first)
    #expect(progress.frame.width >= 250)
}

private extension NSView {
    func descendants<T: NSView>(of type: T.Type) -> [T] {
        subviews.flatMap { view in
            (view as? T).map { [$0] } ?? view.descendants(of: type)
        }
    }
}
