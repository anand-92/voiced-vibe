import SwiftUI

struct SidebarView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        @Bindable var state = appState

        VStack(spacing: 0) {
            // Header
            HStack(spacing: 8) {
                RoundedRectangle(cornerRadius: 4)
                    .fill(.white.opacity(0.1))
                    .frame(width: 24, height: 24)
                    .overlay {
                        Text("VV")
                            .font(.system(size: 8, weight: .bold, design: .monospaced))
                            .foregroundStyle(.white)
                    }
                Text("Voiced Vibe")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.white.opacity(0.85))
                Spacer()
            }
            .padding(.horizontal, 16)
            .frame(height: 48)
            .background(.white.opacity(0.02))

            Divider().opacity(0.2)

            // Waveform + Mic Button
            ZStack {
                WaveformView(rmsLevel: appState.audioManager.getRMSLevel())
                    .opacity(0.6)

                VStack(spacing: 12) {
                    Button {
                        // Always-live mode; mic stays on automatically.
                    } label: {
                        Image(systemName: "mic.fill")
                            .font(.system(size: 22))
                            .foregroundStyle(appState.isConnected ? .black : .secondary)
                            .frame(width: 56, height: 56)
                            .background(
                                appState.isConnected ? Color.white : Color.gray.opacity(0.3),
                                in: Circle()
                            )
                            .shadow(color: .black.opacity(0.3), radius: 8)
                    }
                    .buttonStyle(.plain)

                    if appState.micPermission == .denied || appState.micPermission == .restricted {
                        VStack(spacing: 6) {
                            Image(systemName: "mic.slash.fill")
                                .font(.system(size: 16))
                                .foregroundStyle(.red)
                            Text("Microphone access denied")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(.red.opacity(0.9))
                            Button("Open System Settings") {
                                if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone") {
                                    NSWorkspace.shared.open(url)
                                }
                            }
                            .font(.system(size: 11, weight: .medium))
                            .buttonStyle(.bordered)
                            .tint(.red)
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(.red.opacity(0.1), in: RoundedRectangle(cornerRadius: 8))
                    } else {
                        HStack(spacing: 6) {
                            Circle()
                                .fill(appState.statusTone)
                                .frame(width: 7, height: 7)
                                .shadow(color: appState.statusTone.opacity(0.5), radius: 4)

                            Text(appState.statusText)
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .frame(height: 200)
            .background(LinearGradient(colors: [.clear, .black.opacity(0.2)], startPoint: .top, endPoint: .bottom))

            Divider().opacity(0.2)

            // Settings
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    // Workspace
                    VStack(alignment: .leading, spacing: 4) {
                        Text("WORKSPACE")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(.secondary)
                            .tracking(1.5)

                        Text(appState.projectPath?.components(separatedBy: "/").last ?? "Unknown")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(.white.opacity(0.85))

                        if let path = appState.projectPath {
                            Text(path)
                                .font(.system(size: 10))
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }

                        Button("Change...") {
                            Task { await appState.changeProject() }
                        }
                        .font(.system(size: 11, weight: .medium))
                        .padding(.top, 4)
                    }

                    // Language
                    VStack(alignment: .leading, spacing: 4) {
                        Text("LANGUAGE")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(.secondary)
                            .tracking(1.5)

                        Picker("", selection: $state.language) {
                            ForEach(supportedLanguages, id: \.code) { lang in
                                Text(lang.name).tag(lang.code)
                            }
                        }
                        .labelsHidden()
                    }

                    Spacer()

                    Divider().opacity(0.2)

                    // Actions
                    VStack(spacing: 8) {
                        Button {
                            Task { await appState.handleNewChat() }
                        } label: {
                            Label("Clear Context", systemImage: "message")
                                .font(.system(size: 12, weight: .medium))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 8)
                        }
                        .buttonStyle(.bordered)

                        Button {
                            Task { await appState.handleConnectToggle() }
                        } label: {
                            Label(
                                appState.isConnected ? "Disconnect" : "Connect",
                                systemImage: "power"
                            )
                            .font(.system(size: 12, weight: .medium))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 8)
                        }
                        .buttonStyle(.bordered)
                        .tint(appState.isConnected ? .red : .white)
                    }
                }
                .padding(16)
            }
        }
        .frame(width: 280)
        .background(.black.opacity(0.5))
    }
}

// MARK: - Waveform Visualization

struct WaveformView: View {
    var rmsLevel: Float

    @State private var phase: Double = 0

    private let layers: [(frequency: Double, amplitude: Double, speed: Double, color: Color)] = [
        (0.015, 30, 0.05, Color(red: 0.26, green: 0.52, blue: 0.96).opacity(0.6)),
        (0.02, 20, 0.07, Color(red: 0.61, green: 0.45, blue: 0.80).opacity(0.6)),
        (0.01, 25, 0.03, Color(red: 0.85, green: 0.40, blue: 0.44).opacity(0.6)),
        (0.025, 15, 0.09, Color(red: 0.26, green: 0.77, blue: 0.96).opacity(0.6)),
    ]

    var body: some View {
        TimelineView(.animation) { timeline in
            Canvas { context, size in
                let centerY = size.height / 2
                let level = Double(max(min(rmsLevel, 1.0), 0)) * 1.5 + 0.1

                let elapsed = timeline.date.timeIntervalSinceReferenceDate

                for (index, layer) in layers.enumerated() {
                    let layerPhase = elapsed * layer.speed * 60 + Double(index) * 1.0

                    var path = Path()
                    path.move(to: CGPoint(x: 0, y: centerY))

                    for x in stride(from: 0, through: size.width, by: 2) {
                        let taper = sin((x / size.width) * .pi)
                        let y = centerY + sin(x * layer.frequency + layerPhase) * layer.amplitude * level * taper
                        path.addLine(to: CGPoint(x: x, y: y))
                    }

                    context.stroke(
                        path,
                        with: .color(layer.color),
                        lineWidth: 4 + CGFloat(rmsLevel) * 10
                    )
                }
            }
        }
    }
}
