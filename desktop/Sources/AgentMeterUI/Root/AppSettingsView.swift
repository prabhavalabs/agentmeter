import SwiftUI

/// The standard ⌘, Settings window. Wraps the shared settings form so the
/// window and the main window's Settings sidebar section stay identical.
public struct AppSettingsView: View {
    public init() {}

    public var body: some View {
        ApplicationSettingsForm()
            .padding(12)
            .frame(width: 520, height: 460)
    }
}
