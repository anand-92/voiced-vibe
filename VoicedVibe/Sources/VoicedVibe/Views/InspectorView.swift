import SwiftUI

struct InspectorView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Label("Inspector", systemImage: "waveform.path.ecg")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.white.opacity(0.85))

                Spacer()

                Text("\(appState.visibleTimeline.count) events")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(.white.opacity(0.05), in: Capsule())
            }
            .padding(.horizontal, 16)
            .frame(height: 48)

            Divider().opacity(0.2)

            // Filters
            FlowLayout(spacing: 6) {
                ForEach(filterGroups) { group in
                    FilterToggle(group: group, isActive: appState.filters[group.id] != false) {
                        var updated = appState.filters
                        updated[group.id] = !(appState.filters[group.id] ?? true)
                        appState.filters = updated
                    }
                }
            }
            .padding(12)

            Divider().opacity(0.2)

            // Timeline
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 10) {
                        if appState.visibleTimeline.isEmpty {
                            Text("No activity yet.")
                                .font(.system(size: 12))
                                .foregroundStyle(.secondary)
                                .padding(.top, 40)
                        } else {
                            ForEach(appState.visibleTimeline) { entry in
                                TimelineCardView(entry: entry)
                                    .id(entry.id)
                            }
                        }
                    }
                    .padding(12)
                }
                .onChange(of: appState.timeline.count) { _, _ in
                    if let last = appState.visibleTimeline.last {
                        withAnimation(.easeOut(duration: 0.2)) {
                            proxy.scrollTo(last.id, anchor: .bottom)
                        }
                    }
                }
            }
        }
        .frame(width: 340)
        .background(.black.opacity(0.3))
    }
}

struct FilterToggle: View {
    let group: FilterGroup
    let isActive: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: group.sfSymbol)
                    .font(.system(size: 11))
                Text(group.label)
                    .font(.system(size: 10, weight: .medium))
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(isActive ? .white.opacity(0.08) : .clear, in: RoundedRectangle(cornerRadius: 5))
            .foregroundStyle(isActive ? .white.opacity(0.8) : .secondary)
        }
        .buttonStyle(.plain)
    }
}

struct FlowLayout: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let result = arrange(proposal: proposal, subviews: subviews)
        return result.size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = arrange(proposal: proposal, subviews: subviews)
        for (index, position) in result.positions.enumerated() {
            subviews[index].place(
                at: CGPoint(x: bounds.minX + position.x, y: bounds.minY + position.y),
                proposal: .unspecified
            )
        }
    }

    private func arrange(proposal: ProposedViewSize, subviews: Subviews) -> (size: CGSize, positions: [CGPoint]) {
        let maxWidth = proposal.width ?? .infinity
        var positions: [CGPoint] = []
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0
        var totalHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > maxWidth, x > 0 {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            positions.append(CGPoint(x: x, y: y))
            rowHeight = max(rowHeight, size.height)
            x += size.width + spacing
            totalHeight = max(totalHeight, y + rowHeight)
        }

        return (CGSize(width: maxWidth, height: totalHeight), positions)
    }
}
