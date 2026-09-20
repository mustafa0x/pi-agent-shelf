import SwiftUI

struct ShelfView: View {
    @ObservedObject var store: AgentStore
    let onSelect: (PiAgent) -> Void

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            content
        }
        .frame(minWidth: 560, idealWidth: 980, minHeight: 174, idealHeight: 174)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var header: some View {
        HStack(spacing: 10) {
            Text("Pi agents")
                .font(.headline)

            Text("\(store.agents.count)")
                .font(.caption.weight(.semibold))
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .padding(.horizontal, 7)
                .padding(.vertical, 3)
                .background(.quaternary, in: Capsule())

            Spacer()

            Text("Newest first")
                .font(.caption)
                .foregroundStyle(.tertiary)

            Button {
                store.refresh()
            } label: {
                if store.isRefreshing {
                    ProgressView()
                        .controlSize(.small)
                        .frame(width: 16, height: 16)
                } else {
                    Image(systemName: "arrow.clockwise")
                        .frame(width: 16, height: 16)
                }
            }
            .buttonStyle(.plain)
            .help("Refresh")
            .disabled(store.isRefreshing)
        }
        .padding(.horizontal, 14)
        .frame(height: 42)
    }

    @ViewBuilder
    private var content: some View {
        if let errorMessage = store.errorMessage, store.agents.isEmpty {
            ContentUnavailableView(
                "Ghostty is unavailable",
                systemImage: "terminal",
                description: Text(errorMessage)
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if store.agents.isEmpty && store.isRefreshing {
            VStack(spacing: 8) {
                ProgressView()
                    .controlSize(.small)
                Text("Scanning Ghostty…")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if store.agents.isEmpty {
            ContentUnavailableView(
                "No live pi agents",
                systemImage: "rectangle.stack",
                description: Text("Open pi in Ghostty and it will appear here.")
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 10) {
                    ForEach(store.agents) { agent in
                        Button {
                            onSelect(agent)
                        } label: {
                            AgentCard(agent: agent)
                        }
                        .buttonStyle(.plain)
                        .help(agent.cwd)
                        .accessibilityLabel("\(agent.displayName), \(agent.state.rawValue), last active \(relativeActivity(agent.lastActivity))")
                    }
                }
                .padding(12)
            }
        }
    }

    private func relativeActivity(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}

private struct AgentCard: View {
    let agent: PiAgent
    @State private var isHovering = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 6) {
                Circle()
                    .fill(stateColor)
                    .frame(width: 7, height: 7)

                Text(agent.state.rawValue)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(stateColor)

                Spacer(minLength: 8)

                Text(relativeActivity)
                    .font(.caption)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 10)

            Text(agent.displayName)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.primary)
                .lineLimit(1)

            Text(agent.projectName)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .padding(.top, 3)

            Spacer(minLength: 9)

            HStack {
                Text(agent.shortSessionID)
                    .font(.caption2)
                    .monospaced()
                    .foregroundStyle(.tertiary)

                Spacer()

                Image(systemName: "arrow.up.forward.app")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(isHovering ? Color.accentColor : Color(nsColor: .tertiaryLabelColor))
            }
        }
        .padding(12)
        .frame(width: 196, height: 106, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .fill(isHovering ? Color(nsColor: .selectedContentBackgroundColor).opacity(0.1) : Color(nsColor: .controlBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .strokeBorder(isHovering ? Color.accentColor.opacity(0.55) : Color(nsColor: .separatorColor), lineWidth: 1)
        )
        .contentShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
        .onHover { isHovering = $0 }
    }

    private var stateColor: Color {
        switch agent.state {
        case .working:
            return .accentColor
        case .idle:
            return Color(nsColor: .secondaryLabelColor)
        case .unknown:
            return .orange
        }
    }

    private var relativeActivity: String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: agent.lastActivity, relativeTo: Date())
    }
}
