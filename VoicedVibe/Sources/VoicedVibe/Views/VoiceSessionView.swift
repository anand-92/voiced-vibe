import SwiftUI

struct VoiceSessionView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        HStack(spacing: 0) {
            SidebarView()

            Divider().opacity(0.2)

            ChatAreaView()

            Divider().opacity(0.2)

            InspectorView()
        }
        .onKeyPress(.space) {
            guard appState.mode != .alwaysOn else { return .ignored }
            appState.audioManager.toggleCapture()
            return .handled
        }
    }
}
