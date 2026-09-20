import SwiftUI

struct ShelfView: View {
    @ObservedObject var store: AgentStore
    let onSelect: (PiAgent) -> Void

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            if let focusError = store.focusError {
                HStack(spacing: 7) {
                    Image(systemName: "exclamationmark.triangle.fill")
                    Text(focusError)
                        .lineLimit(2)
                    Spacer()
                }
                .font(.caption)
                .foregroundStyle(.red)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                Divider()
            }
            content
        }
        .frame(minWidth: 480, idealWidth: 620, minHeight: 360, idealHeight: 640)
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
                Image(systemName: "arrow.clockwise")
                    .frame(width: 16, height: 16)
            }
            .buttonStyle(.plain)
            .focusEffectDisabled()
            .help("Refresh")
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
        } else if store.agents.isEmpty {
            ContentUnavailableView(
                "No live pi agents",
                systemImage: "rectangle.stack",
                description: Text("Open pi in Ghostty and it will appear here.")
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollView(.vertical) {
                LazyVStack(spacing: 0) {
                    ForEach(store.agents) { agent in
                        Button {
                            onSelect(agent)
                        } label: {
                            AgentRow(agent: agent)
                        }
                        .buttonStyle(.plain)
                        .help("\(agent.displayCWD)\n\(agent.model ?? "Unknown model")\nSession \(agent.shortSessionID)")
                        .accessibilityLabel("\(agent.displayName), \(agent.state.rawValue), last active \(relativeActivity(agent.lastActivity))")

                        Divider()
                            .padding(.leading, 40)
                    }
                }
            }
            .clipped()
        }
    }

    private func relativeActivity(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}

private struct AgentRow: View {
    let agent: PiAgent
    @State private var isHovering = false

    var body: some View {
        HStack(spacing: 10) {
            Circle()
                .fill(stateColor)
                .frame(width: 7, height: 7)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 8) {
                    Text(agent.displayName)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)

                    if isHovering {
                        Text(agent.shortSessionID)
                            .font(.caption2)
                            .monospaced()
                            .foregroundStyle(.tertiary)
                    }

                    Spacer(minLength: 8)

                    Text(agent.state.rawValue)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(stateColor)

                    Text(relativeActivity)
                        .font(.caption)
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }

                HStack(spacing: 10) {
                    Text(agent.displayCWD)
                        .truncationMode(.middle)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    if let model = agent.model {
                        Text(model)
                            .lineLimit(1)
                            .frame(maxWidth: 220, alignment: .trailing)
                    }
                }
                .font(.caption2)
                .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 12)
        .frame(maxWidth: .infinity, minHeight: 46, maxHeight: 46, alignment: .leading)
        .background(isHovering ? Color.accentColor.opacity(0.09) : Color.clear)
        .contentShape(Rectangle())
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
