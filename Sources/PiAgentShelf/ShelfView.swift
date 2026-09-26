import SwiftUI

struct ShelfView: View {
    @ObservedObject var store: AgentStore
    let onSelect: (PiAgent) -> Void
    var onDismiss: () -> Void = {}
    @State private var query = ""
    @AppStorage("idleOnly") private var idleOnly = false
    @FocusState private var searchFocused: Bool
    @FocusState private var focusedAgentID: PiAgent.ID?

    private var filteredAgents: [PiAgent] {
        let words = query.split(whereSeparator: \.isWhitespace).map(String.init)
        return store.agents.filter { agent in
            guard !idleOnly || agent.state == .idle else { return false }
            let text = [agent.displayName, agent.projectName, agent.cwd, agent.displayCWD,
                        agent.model ?? "", agent.thinkingLevel ?? "", agent.sessionID].joined(separator: " ")
            return words.allSatisfy { word in
                switch word.lowercased() {
                case "#idle":
                    return agent.state == .idle
                case "#working":
                    return agent.state == .working
                default:
                    return text.localizedCaseInsensitiveContains(word)
                }
            }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("Filter agents", text: $query)
                    .textFieldStyle(.plain)
                    .focused($searchFocused)
                    .onSubmit {
                        if let agent = filteredAgents.first { onSelect(agent) }
                    }
                    .onKeyPress(.downArrow) {
                        focusedAgentID = filteredAgents.first?.id
                        return .handled
                    }
                Toggle("Idle ⌘I", isOn: $idleOnly)
                    .toggleStyle(.button)
                    .controlSize(.small)
                    .keyboardShortcut("i", modifiers: .command)
                    .help("Show only idle agents (Command–I)")
                    .onChange(of: idleOnly) { _, _ in
                        focusedAgentID = nil
                        searchFocused = true
                    }
            }
            .padding(.horizontal, 14)
            .padding(.bottom, 12)
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
        .onAppear { searchFocused = true }
        .onExitCommand {
            if query.isEmpty && !idleOnly {
                onDismiss()
            } else {
                query = ""
                idleOnly = false
                focusedAgentID = nil
                searchFocused = true
            }
        }
    }

    private var header: some View {
        HStack(spacing: 10) {
            Text("Pi agents")
                .font(.headline)

            Text(query.isEmpty && !idleOnly ? "\(store.agents.count)" : "\(filteredAgents.count) of \(store.agents.count)")
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
        } else if filteredAgents.isEmpty {
            ContentUnavailableView("No matching agents", systemImage: "magnifyingglass",
                                   description: Text("Try another name, path, model, or session ID."))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollViewReader { proxy in
                ScrollView(.vertical) {
                    VStack(spacing: 0) {
                        ForEach(filteredAgents) { agent in
                            Button {
                                focusedAgentID = agent.id
                                onSelect(agent)
                            } label: {
                                AgentRow(
                                    agent: agent,
                                    isKeyboardFocused: focusedAgentID == agent.id
                                )
                            }
                            .buttonStyle(.plain)
                            .focused($focusedAgentID, equals: agent.id)
                            .focusEffectDisabled()
                            .onMoveCommand { direction in
                                moveFocus(from: agent.id, direction: direction)
                            }
                            .onKeyPress(.return) {
                                onSelect(agent)
                                return .handled
                            }
                            .help("\(agent.displayCWD)\n\(agent.model ?? "Unknown model")\nThinking \(agent.thinkingLevelDescription)\n\(agent.fastModeDescription)\nSession \(agent.shortSessionID)")
                            .accessibilityLabel("\(agent.displayName), \(agent.state.rawValue), thinking \(agent.thinkingLevelDescription), \(agent.fastModeDescription), last active \(relativeActivity(agent.lastActivity))")

                            Divider()
                                .padding(.leading, 40)
                        }
                    }
                }
                .clipped()
                .onChange(of: focusedAgentID) { _, agentID in
                    guard let agentID else { return }
                    proxy.scrollTo(agentID)
                }
                .onChange(of: filteredAgents.map(\.id)) { _, agentIDs in
                    if let focusedAgentID, agentIDs.contains(focusedAgentID) {
                        return
                    }
                    if !searchFocused { focusedAgentID = agentIDs.first }
                }
            }
        }
    }

    private func moveFocus(from agentID: PiAgent.ID, direction: MoveCommandDirection) {
        let agents = filteredAgents
        guard let currentIndex = agents.firstIndex(where: { $0.id == agentID }) else {
            return
        }

        let targetIndex: Int
        switch direction {
        case .up:
            if currentIndex == 0 {
                focusedAgentID = nil
                searchFocused = true
                return
            }
            targetIndex = currentIndex - 1
        case .down:
            targetIndex = min(agents.count - 1, currentIndex + 1)
        default:
            return
        }
        focusedAgentID = agents[targetIndex].id
    }

    private func relativeActivity(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}

private struct AgentRow: View {
    let agent: PiAgent
    let isKeyboardFocused: Bool
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
                        HStack(spacing: 4) {
                            if agent.fastMode == true {
                                Image(systemName: "bolt.fill")
                                    .foregroundStyle(Color.accentColor)
                                    .help("Fast mode on")
                            }
                            Text(model)
                                .lineLimit(1)

                            Text(agent.thinkingLevel ?? "?")
                                .foregroundStyle(.tertiary)
                                .help(agent.thinkingLevelDescription)
                        }
                        .frame(maxWidth: 260, alignment: .trailing)
                    }
                }
                .font(.caption2)
                .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 12)
        .frame(maxWidth: .infinity, minHeight: 46, maxHeight: 46, alignment: .leading)
        .background(isHovering || isKeyboardFocused ? Color.accentColor.opacity(0.09) : Color.clear)
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
