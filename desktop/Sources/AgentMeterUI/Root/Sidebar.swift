import SwiftUI

public struct Sidebar: View {
    @Environment(AppModel.self) private var model

    public init() {}

    public var body: some View {
        @Bindable var preferences = model.preferences
        List(selection: $preferences.selectedSection) {
            Section {
                ForEach(NavigationSection.allCases) { section in
                    NavigationLink(value: section) {
                        Label(section.title, systemImage: section.symbolName)
                            .font(.body.weight(.medium))
                            .padding(.vertical, 3)
                    }
                }
            }

            Section {
                VStack(alignment: .leading, spacing: 7) {
                    Label("Open source", systemImage: "chevron.left.forwardslash.chevron.right")
                        .font(.caption.weight(.medium))
                    Text("AgentMeter \(model.state.bridge.version)")
                        .font(.caption2.monospaced())
                        .foregroundStyle(.tertiary)
                }
                .padding(.vertical, 6)
                .accessibilityElement(children: .combine)
            }
        }
        .listStyle(.sidebar)
        .navigationTitle("AgentMeter")
        .navigationSplitViewColumnWidth(min: 178, ideal: 215, max: 250)
    }
}
