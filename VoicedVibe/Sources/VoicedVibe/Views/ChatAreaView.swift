import SwiftUI

struct ChatAreaView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        @Bindable var state = appState

        VStack(spacing: 0) {
            // Transcript
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 16) {
                        if appState.transcript.isEmpty {
                            Text("System connected. Awaiting voice input.")
                                .font(.system(size: 13))
                                .foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity, alignment: .center)
                                .padding(.top, 60)
                        } else {
                            ForEach(appState.transcript) { entry in
                                TranscriptBubble(entry: entry)
                                    .id(entry.id)
                            }
                        }
                    }
                    .padding(20)
                    .frame(maxWidth: 720)
                    .frame(maxWidth: .infinity)
                }
                .onChange(of: appState.transcript.count) { _, _ in
                    if let last = appState.transcript.last {
                        withAnimation(.easeOut(duration: 0.2)) {
                            proxy.scrollTo(last.id, anchor: .bottom)
                        }
                    }
                }
            }

            Divider().opacity(0.2)

            // Input area
            VStack(spacing: 8) {
                // Attachments
                if !appState.attachments.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(appState.attachments) { attachment in
                                ZStack(alignment: .topTrailing) {
                                    Image(nsImage: attachment.image)
                                        .resizable()
                                        .aspectRatio(contentMode: .fill)
                                        .frame(width: 56, height: 56)
                                        .clipShape(RoundedRectangle(cornerRadius: 8))
                                        .overlay {
                                            RoundedRectangle(cornerRadius: 8)
                                                .strokeBorder(.white.opacity(0.1), lineWidth: 1)
                                        }

                                    Button {
                                        appState.attachments.removeAll { $0.id == attachment.id }
                                    } label: {
                                        Image(systemName: "xmark.circle.fill")
                                            .font(.system(size: 14))
                                            .foregroundStyle(.white)
                                            .background(.black.opacity(0.6), in: Circle())
                                    }
                                    .buttonStyle(.plain)
                                    .offset(x: 4, y: -4)
                                }
                            }
                        }
                        .padding(.horizontal, 4)
                    }
                }

                HStack(alignment: .bottom, spacing: 8) {
                    // Image attach button
                    Button {
                        openImagePicker()
                    } label: {
                        Image(systemName: "photo")
                            .font(.system(size: 16))
                            .foregroundStyle(.secondary)
                            .frame(width: 32, height: 32)
                    }
                    .buttonStyle(.plain)

                    // Text input
                    TextField("Message...", text: $state.textInput, axis: .vertical)
                        .textFieldStyle(.plain)
                        .font(.system(size: 13))
                        .lineLimit(1...6)
                        .onSubmit {
                            Task { await appState.sendText() }
                        }
                        .padding(.vertical, 8)
                        .padding(.horizontal, 12)
                        .background(.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 12))
                        .overlay {
                            RoundedRectangle(cornerRadius: 12)
                                .strokeBorder(.white.opacity(0.08), lineWidth: 1)
                        }

                    // Send button
                    Button {
                        Task { await appState.sendText() }
                    } label: {
                        Image(systemName: "arrow.up")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(.black)
                            .frame(width: 32, height: 32)
                            .background(.white, in: RoundedRectangle(cornerRadius: 8))
                    }
                    .buttonStyle(.plain)
                }

                Text("Press Return to send")
                    .font(.system(size: 10))
                    .foregroundStyle(.quaternary)
            }
            .padding(12)
            .background(.white.opacity(0.02))
        }
    }

    private func openImagePicker() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image]
        panel.allowsMultipleSelection = true

        if panel.runModal() == .OK {
            for url in panel.urls {
                if let image = NSImage(contentsOf: url),
                   let tiffData = image.tiffRepresentation,
                   let bitmap = NSBitmapImageRep(data: tiffData),
                   let pngData = bitmap.representation(using: .png, properties: [:]) {
                    let attachment = AttachmentImage(
                        id: uid("img"),
                        mimeType: "image/png",
                        data: pngData.base64EncodedString(),
                        image: image,
                        name: url.lastPathComponent
                    )
                    appState.attachments.append(attachment)
                }
            }
        }
    }
}

struct TranscriptBubble: View {
    let entry: TranscriptEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(roleLabel)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
                .tracking(1.5)

            Text(entry.text)
                .font(.system(size: 13))
                .foregroundStyle(textColor)
                .italic(entry.role == .narrator)
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(backgroundColor, in: RoundedRectangle(cornerRadius: 12))
                .overlay {
                    if entry.role == .user {
                        RoundedRectangle(cornerRadius: 12)
                            .strokeBorder(.white.opacity(0.06), lineWidth: 1)
                    }
                }
        }
    }

    private var roleLabel: String {
        switch entry.role {
        case .user: "You"
        case .gemini: "Agent"
        case .narrator: "Agent Thinking"
        }
    }

    private var textColor: Color {
        switch entry.role {
        case .user: .white.opacity(0.85)
        case .gemini: .white.opacity(0.7)
        case .narrator: .white.opacity(0.4)
        }
    }

    private var backgroundColor: Color {
        switch entry.role {
        case .user: .white.opacity(0.04)
        case .gemini: .clear
        case .narrator: .clear
        }
    }
}
