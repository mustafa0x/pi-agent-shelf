import AppKit
import SwiftUI

private struct ScreenshotFrame: View {
    let store: AgentStore

    var body: some View {
        ZStack(alignment: .top) {
            Color(red: 0.84, green: 0.89, blue: 0.94)

            VStack(spacing: 0) {
                menuBar

                HStack {
                    Spacer()
                    popover
                }
                .padding(.trailing, 70)
            }
        }
    }

    private var menuBar: some View {
        HStack(spacing: 16) {
            Image(systemName: "apple.logo")
                .font(.system(size: 13, weight: .semibold))

            Text("Finder")
                .fontWeight(.semibold)
            Text("File")
            Text("Edit")
            Text("View")
            Text("Go")
            Text("Window")
            Text("Help")

            Spacer()

            HStack(spacing: 10) {
                Image(systemName: "rectangle.stack")
                    .font(.system(size: 13, weight: .medium))
                    .frame(width: 24, height: 22)
                    .background(.black.opacity(0.09), in: RoundedRectangle(cornerRadius: 5))
                Image(systemName: "wifi")
                    .frame(width: 18)
                Image(systemName: "battery.100percent")
                    .frame(width: 24)
                Image(systemName: "controlcenter")
                    .frame(width: 18)
                Text("Mon 9:41 AM")
                    .frame(width: 88, alignment: .trailing)
            }
        }
        .font(.system(size: 13))
        .foregroundStyle(.black.opacity(0.88))
        .padding(.horizontal, 14)
        .frame(height: 28)
        .background(.white.opacity(0.92))
        .overlay(alignment: .bottom) {
            Divider().opacity(0.45)
        }
    }

    private var popover: some View {
        VStack(spacing: 0) {
            PopoverArrow()
                .fill(Color(nsColor: .windowBackgroundColor))
                .frame(width: 18, height: 9)
                .frame(maxWidth: .infinity, alignment: .trailing)
                .padding(.trailing, 135)

            ShelfView(store: store, onSelect: { _ in })
                .frame(width: 560, height: 360)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(Color(nsColor: .separatorColor).opacity(0.55))
                }
        }
        .shadow(color: .black.opacity(0.24), radius: 20, y: 10)
    }
}

private struct PopoverArrow: Shape {
    func path(in rect: CGRect) -> Path {
        Path { path in
            path.move(to: CGPoint(x: rect.minX, y: rect.maxY))
            path.addLine(to: CGPoint(x: rect.midX, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
            path.closeSubpath()
        }
    }
}

@main
struct RenderReadmeScreenshot {
    @MainActor
    static func main() throws {
        _ = NSApplication.shared
        NSApp.appearance = NSAppearance(named: .aqua)

        let defaultsName = "PiAgentShelf.ReadmeScreenshot"
        let defaults = UserDefaults(suiteName: defaultsName)!
        defaults.removePersistentDomain(forName: defaultsName)
        defaults.set(false, forKey: "idleOnly")
        defer { defaults.removePersistentDomain(forName: defaultsName) }

        let now = Date()
        let agents = [
            agent(
                pid: 1101,
                project: "atlas-api",
                sessionName: "Implement audit log",
                sessionID: "demo0001-0000-0000-0000-000000000001",
                model: "gpt-5.6-sol",
                fastMode: true,
                activity: now.addingTimeInterval(-8),
                state: .working
            ),
            agent(
                pid: 1102,
                project: "web-console",
                sessionName: "Fix auth redirect",
                sessionID: "demo0002-0000-0000-0000-000000000002",
                model: "claude-sonnet-4-6",
                fastMode: nil,
                activity: now.addingTimeInterval(-120),
                state: .idle
            ),
            agent(
                pid: 1103,
                project: "desktop-client",
                sessionName: nil,
                sessionID: "demo0003-0000-0000-0000-000000000003",
                model: "gpt-5.5",
                fastMode: false,
                activity: now.addingTimeInterval(-420),
                state: .idle
            ),
            agent(
                pid: 1104,
                project: "release-tools",
                sessionName: "Review release notes",
                sessionID: "demo0004-0000-0000-0000-000000000004",
                model: "gpt-5.4",
                fastMode: false,
                activity: now.addingTimeInterval(-720),
                state: .working
            ),
            agent(
                pid: 1105,
                project: "test-suite",
                sessionName: "Investigate flaky test",
                sessionID: "demo0005-0000-0000-0000-000000000005",
                model: "claude-opus-4-6",
                fastMode: nil,
                activity: now.addingTimeInterval(-3_600),
                state: .idle
            ),
        ]

        let root = ScreenshotFrame(store: AgentStore(agents: agents))
            .defaultAppStorage(defaults)
            .environment(\.colorScheme, .light)

        let size = NSSize(width: 760, height: 430)
        let host = NSHostingView(rootView: root)
        host.frame = NSRect(origin: .zero, size: size)
        host.wantsLayer = true
        host.layer?.backgroundColor = NSColor.clear.cgColor
        host.layoutSubtreeIfNeeded()

        guard let image = host.bitmapImageRepForCachingDisplay(in: host.bounds) else {
            throw ScreenshotError.renderFailed
        }
        host.cacheDisplay(in: host.bounds, to: image)

        guard let png = image.representation(using: .png, properties: [:]) else {
            throw ScreenshotError.encodingFailed
        }

        let outputPath = CommandLine.arguments.dropFirst().first ?? "docs/pi-agent-shelf.png"
        let outputURL = URL(fileURLWithPath: outputPath)
        try FileManager.default.createDirectory(
            at: outputURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try png.write(to: outputURL, options: .atomic)
    }

    private static func agent(
        pid: Int32,
        project: String,
        sessionName: String?,
        sessionID: String,
        model: String,
        fastMode: Bool?,
        activity: Date,
        state: AgentState
    ) -> PiAgent {
        PiAgent(
            pid: pid,
            tty: "/dev/ttys\(pid - 1100)",
            cwd: "/workspace/\(project)",
            sessionID: sessionID,
            sessionFile: "/tmp/\(sessionID).jsonl",
            sessionName: sessionName,
            provider: "demo",
            model: model,
            fastMode: fastMode,
            ghosttyTarget: GhosttyTarget(
                bundleIdentifier: "com.mitchellh.ghostty",
                processIdentifier: 100,
                name: "Ghostty"
            ),
            lastActivity: activity,
            state: state
        )
    }

    private enum ScreenshotError: Error {
        case renderFailed
        case encodingFailed
    }
}
