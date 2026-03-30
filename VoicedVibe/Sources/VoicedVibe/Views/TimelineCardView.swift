import SwiftUI

struct TimelineCardView: View {
    let entry: TimelineEntry

    @State private var expanded = false

    var body: some View {
        switch entry {
        case .message(let msg):
            messageCard(msg)
        case .diff(let diff):
            diffCard(diff)
        }
    }

    @ViewBuilder
    private func messageCard(_ entry: TimelineMessageEntry) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(entry.tag)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)
                    .tracking(0.8)

                Spacer()

                Text(entry.time)
                    .font(.system(size: 9))
                    .foregroundStyle(.quaternary)
            }

            if entry.renderMarkdown, looksLikeMarkdown(entry.detail) {
                if let attributed = try? AttributedString(markdown: entry.detail) {
                    Text(attributed)
                        .font(.system(size: 11))
                        .foregroundStyle(.white.opacity(0.7))
                        .textSelection(.enabled)
                } else {
                    Text(entry.detail)
                        .font(.system(size: 11))
                        .foregroundStyle(.white.opacity(0.7))
                        .textSelection(.enabled)
                }
            } else {
                Text(entry.detail)
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.7))
                    .lineLimit(expanded ? nil : 3)
                    .textSelection(.enabled)
            }
        }
        .padding(.bottom, 8)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(.white.opacity(0.03))
                .frame(height: 1)
        }
    }

    @ViewBuilder
    private func diffCard(_ entry: TimelineDiffEntry) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Image(systemName: "doc.text")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)

                Text(entry.tag)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)
                    .tracking(0.8)

                Spacer()

                Text(entry.time)
                    .font(.system(size: 9))
                    .foregroundStyle(.quaternary)
            }

            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(URL(fileURLWithPath: entry.filePath).lastPathComponent)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.7))

                    Spacer()

                    Button {
                        expanded.toggle()
                    } label: {
                        Text(expanded ? "Collapse" : "Expand")
                            .font(.system(size: 9, weight: .medium))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 4))
                            .overlay {
                                RoundedRectangle(cornerRadius: 4)
                                    .strokeBorder(.white.opacity(0.1), lineWidth: 1)
                            }
                    }
                    .buttonStyle(.plain)
                }

                if expanded {
                    ScrollView(.horizontal, showsIndicators: false) {
                        VStack(alignment: .leading, spacing: 0) {
                            if !entry.oldStr.isEmpty {
                                ForEach(Array(entry.oldStr.components(separatedBy: "\n").enumerated()), id: \.offset) { _, line in
                                    Text("- \(line)")
                                        .font(.system(size: 10, design: .monospaced))
                                        .foregroundStyle(.red.opacity(0.7))
                                }
                            }
                            ForEach(Array(entry.newStr.components(separatedBy: "\n").enumerated()), id: \.offset) { _, line in
                                Text("+ \(line)")
                                    .font(.system(size: 10, design: .monospaced))
                                    .foregroundStyle(.green.opacity(0.7))
                            }
                        }
                        .padding(8)
                    }
                    .background(.black, in: RoundedRectangle(cornerRadius: 6))
                    .overlay {
                        RoundedRectangle(cornerRadius: 6)
                            .strokeBorder(.white.opacity(0.05), lineWidth: 1)
                    }
                }
            }
            .padding(10)
            .background(.white.opacity(0.02), in: RoundedRectangle(cornerRadius: 10))
            .overlay {
                RoundedRectangle(cornerRadius: 10)
                    .strokeBorder(.white.opacity(0.05), lineWidth: 1)
            }
        }
    }
}
