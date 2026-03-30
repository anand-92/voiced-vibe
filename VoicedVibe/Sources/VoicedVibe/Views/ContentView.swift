import SwiftUI

struct ContentView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        Group {
            switch appState.screen {
            case .picker:
                ProjectPickerView()
            case .voice:
                VoiceSessionView()
            }
        }
        .frame(minWidth: 900, minHeight: 600)
        .preferredColorScheme(.dark)
        .task {
            await appState.startBackend()

            let baseURL = await appState.pythonBackend.baseURL
            do {
                let url = URL(string: "\(baseURL)/api/project")!
                let (data, _) = try await URLSession.shared.data(from: url)
                let response = try JSONDecoder().decode(ProjectResponse.self, from: data)
                if let active = response.active, active, let path = response.path {
                    appState.projectPath = path
                    appState.screen = .voice
                    await appState.initVoiceUI()
                }
            } catch {
                // Backend not ready yet or no project pre-selected
            }
        }
    }
}
