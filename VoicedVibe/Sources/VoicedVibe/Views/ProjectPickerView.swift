import SwiftUI

struct ProjectPickerView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            VStack(spacing: 24) {
                // Header
                HStack(spacing: 10) {
                    RoundedRectangle(cornerRadius: 6)
                        .fill(.white.opacity(0.9))
                        .frame(width: 32, height: 32)
                        .overlay {
                            Text("VV")
                                .font(.system(size: 10, weight: .bold, design: .monospaced))
                                .foregroundStyle(.black)
                        }
                    Text("Voiced Vibe")
                        .font(.title2.weight(.semibold))
                        .foregroundStyle(.white)
                }

                // Open Folder Button
                Button {
                    openFolderPanel()
                } label: {
                    Label("Open Project Folder...", systemImage: "folder")
                        .font(.system(size: 14, weight: .medium))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                }
                .buttonStyle(.borderedProminent)
                .tint(.white)
                .foregroundStyle(.black)

                if let error = appState.projectError {
                    HStack(spacing: 6) {
                        Image(systemName: "exclamationmark.circle")
                            .font(.system(size: 12))
                        Text(error)
                            .font(.system(size: 11))
                    }
                    .foregroundStyle(.red.opacity(0.9))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(.red.opacity(0.1), in: RoundedRectangle(cornerRadius: 8))
                }

                // Backend status
                if let backendError = appState.backendError {
                    HStack(spacing: 6) {
                        Image(systemName: "exclamationmark.triangle")
                            .font(.system(size: 12))
                        Text("Backend: \(backendError)")
                            .font(.system(size: 11))
                    }
                    .foregroundStyle(.orange)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(.orange.opacity(0.1), in: RoundedRectangle(cornerRadius: 8))
                } else if !appState.backendReady {
                    HStack(spacing: 8) {
                        ProgressView()
                            .controlSize(.small)
                        Text("Starting backend...")
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                    }
                }

                // Recent projects
                if !appState.recentProjects.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("RECENT WORKSPACES")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(.secondary)
                            .tracking(1.5)

                        VStack(spacing: 2) {
                            ForEach(appState.recentProjects, id: \.self) { path in
                                Button {
                                    Task { await appState.openProject(path) }
                                } label: {
                                    HStack(spacing: 10) {
                                        Image(systemName: "folder")
                                            .font(.system(size: 13))
                                            .foregroundStyle(.secondary)
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(URL(fileURLWithPath: path).lastPathComponent)
                                                .font(.system(size: 12, weight: .medium))
                                                .foregroundStyle(.primary)
                                            Text(path)
                                                .font(.system(size: 10))
                                                .foregroundStyle(.tertiary)
                                                .lineLimit(1)
                                                .truncationMode(.middle)
                                        }
                                        Spacer()
                                    }
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 6)
                                    .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                                .background(.white.opacity(0.03), in: RoundedRectangle(cornerRadius: 6))
                            }
                        }
                    }
                }
            }
            .padding(32)
            .frame(maxWidth: 480)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
            .overlay {
                RoundedRectangle(cornerRadius: 16)
                    .strokeBorder(.white.opacity(0.1), lineWidth: 1)
            }

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.black)
    }

    private func openFolderPanel() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.message = "Select a project folder"
        panel.prompt = "Open"

        if panel.runModal() == .OK, let url = panel.url {
            Task { await appState.openProject(url.path) }
        }
    }
}
