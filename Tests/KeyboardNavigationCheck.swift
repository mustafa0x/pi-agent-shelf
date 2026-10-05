import AppKit
import SwiftUI

@main
struct CheckKeyboardNavigation {
    @MainActor
    static func main() {
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        let suite = "PiAgentShelf.FocusCheck"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        defer { defaults.removePersistentDomain(forName: suite) }
        let agents = [("working", AgentState.working), ("idle-a", .idle), ("idle-b", .idle)].enumerated().map { index, item in
            PiAgent(pid: Int32(index + 1), tty: "/dev/ttys\(index)", cwd: "/workspace/\(item.0)",
                    sessionID: item.0, sessionFile: "/tmp/demo.jsonl", sessionName: nil, provider: nil,
                    model: nil, thinkingLevel: nil, fastMode: nil,
                    ghosttyTarget: GhosttyTarget(bundleIdentifier: "demo", processIdentifier: 100, name: "Demo"),
                    lastActivity: Date(), stoppedAt: nil, state: item.1)
        }
        var openedID: String?
        let root = ShelfView(store: AgentStore(agents: agents), onSelect: { openedID = $0.id }).defaultAppStorage(defaults)
        let window = NSWindow(contentRect: NSRect(x: 100, y: 100, width: 560, height: 600),
                              styleMask: [.titled], backing: .buffered, defer: false)
        window.contentViewController = NSHostingController(rootView: root)
        window.makeKeyAndOrderFront(nil)
        app.activate(ignoringOtherApps: true)
        RunLoop.main.run(until: Date().addingTimeInterval(0.5))
        precondition(window.firstResponder is NSTextView, "Search did not get initial focus")
        for expected in [true, false, true, false] {
            let event = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [.command],
                                       timestamp: 0, windowNumber: window.windowNumber, context: nil,
                                       characters: "i", charactersIgnoringModifiers: "i", isARepeat: false, keyCode: 34)!
            precondition(window.performKeyEquivalent(with: event), "Command-I was not handled")
            RunLoop.main.run(until: Date().addingTimeInterval(0.2))
            precondition(defaults.bool(forKey: "idleOnly") == expected, "Idle filter did not toggle")
            precondition(window.firstResponder is NSTextView, "Search lost focus after Command-I")
        }
        for (character, code) in [("\u{f701}", UInt16(125)), ("\u{f701}", 125), ("\u{f700}", 126), ("\u{f701}", 125), ("\r", 36)] {
            let event = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0,
                                       windowNumber: window.windowNumber, context: nil, characters: character,
                                       charactersIgnoringModifiers: character, isARepeat: false, keyCode: code)!
            window.sendEvent(event)
            RunLoop.main.run(until: Date().addingTimeInterval(0.1))
            precondition(window.firstResponder is NSTextView, "Search lost focus during arrow navigation")
        }
        precondition(openedID == "idle-a", "Enter did not open the highlighted agent: \(openedID ?? "none")")
        let editor = window.firstResponder as! NSTextView
        editor.insertText("idle-b", replacementRange: NSRange(location: NSNotFound, length: 0))
        RunLoop.main.run(until: Date().addingTimeInterval(0.2))
        precondition(editor.string == "idle-b", "Typing did not reach search")
        let enter = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0,
                                   windowNumber: window.windowNumber, context: nil, characters: "\r",
                                   charactersIgnoringModifiers: "\r", isARepeat: false, keyCode: 36)!
        window.sendEvent(enter)
        RunLoop.main.run(until: Date().addingTimeInterval(0.1))
        precondition(openedID == "idle-b", "Typing did not reset selection and filter agents")
        window.orderOut(nil)
        print("Command-I, up/down, Enter, and typing preserve search focus and selection behavior")
    }
}
