import SwiftUI

public struct Sidebar: View {
    @Binding private var selection: NavigationSection
    private let version: String

    public init(
        selection: Binding<NavigationSection>,
        version: String = Bundle.main.object(
            forInfoDictionaryKey: "CFBundleShortVersionString"
        ) as? String ?? "Development"
    ) {
        _selection = selection
        self.version = version
    }

    public var body: some View {
        List(selection: $selection) {
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
                    Text("AgentMeter \(version)")
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
