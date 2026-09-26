import XCTest
@testable import PiAgentShelf

final class AgentScannerTests: XCTestCase {
    private var directory: URL!

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try FileManager.default.removeItem(at: directory)
    }

    func testDiscoversAgentsAcrossAllRunningGhosttyProcesses() throws {
        let standard = GhosttyTarget(
            bundleIdentifier: "com.mitchellh.ghostty",
            processIdentifier: 100,
            name: "Ghostty"
        )
        let diagnostics = GhosttyTarget(
            bundleIdentifier: "com.mitchellh.ghostty.diagnostics",
            processIdentifier: 200,
            name: "Ghostty Diagnostics"
        )
        let processes = [
            ProcessRecord(pid: 100, parentPID: 1, tty: "??", command: "/Applications/Ghostty.app/Contents/MacOS/ghostty"),
            ProcessRecord(pid: 110, parentPID: 100, tty: "ttys001", command: "/usr/bin/login"),
            ProcessRecord(pid: 111, parentPID: 110, tty: "ttys001", command: "/bin/zsh"),
            ProcessRecord(pid: 112, parentPID: 111, tty: "ttys001", command: "/usr/local/bin/pi"),
            ProcessRecord(pid: 200, parentPID: 1, tty: "??", command: "/Applications/Ghostty Diagnostics.app/Contents/MacOS/ghostty"),
            ProcessRecord(pid: 210, parentPID: 200, tty: "ttys002", command: "/usr/bin/login"),
            ProcessRecord(pid: 211, parentPID: 210, tty: "ttys002", command: "/bin/zsh"),
            ProcessRecord(pid: 212, parentPID: 211, tty: "ttys002", command: "/usr/local/bin/pi"),
            ProcessRecord(pid: 300, parentPID: 1, tty: "ttys003", command: "/usr/local/bin/pi"),
        ]
        try writeRuntime(pid: 112, sessionID: "standard", project: "standard-project")
        try writeRuntime(pid: 212, sessionID: "diagnostics", project: "diagnostics-project", thinkingLevel: "medium")
        try writeRuntime(pid: 300, sessionID: "outside", project: "outside-project")

        let scanner = AgentScanner(runtimeDirectory: directory) { processes }
        let result = scanner.scan(ghosttyTargets: [standard, diagnostics])

        XCTAssertNil(result.errorMessage)
        XCTAssertEqual(Set(result.agents.map(\.sessionID)), ["standard", "diagnostics"])
        XCTAssertEqual(
            Dictionary(uniqueKeysWithValues: result.agents.map { ($0.sessionID, $0.ghosttyTarget.processIdentifier) }),
            ["standard": 100, "diagnostics": 200]
        )
        XCTAssertEqual(
            Dictionary(uniqueKeysWithValues: result.agents.map { ($0.sessionID, $0.tty) }),
            ["standard": "/dev/ttys001", "diagnostics": "/dev/ttys002"]
        )
        XCTAssertEqual(
            Dictionary(uniqueKeysWithValues: result.agents.map { ($0.sessionID, $0.thinkingLevel) }),
            ["standard": "high", "diagnostics": "medium"]
        )
    }

    private func writeRuntime(
        pid: Int,
        sessionID: String,
        project: String,
        thinkingLevel: String? = nil
    ) throws {
        let sessionURL = directory.appendingPathComponent("\(sessionID).jsonl")
        let session = """
        {"type":"thinking_level_change","thinkingLevel":"high"}
        {"type":"message","message":{"role":"assistant","provider":"openai-codex","model":"gpt-5.6","stopReason":"stop"}}
        """
        try session.write(to: sessionURL, atomically: true, encoding: .utf8)

        var runtime: [String: Any] = [
            "pid": pid,
            "session_id": sessionID,
            "session_file": sessionURL.path,
            "cwd": "/workspace/\(project)",
            "updated_at": "2026-09-22T10:00:00Z",
        ]
        if let thinkingLevel {
            runtime["thinking_level"] = thinkingLevel
        }
        let data = try JSONSerialization.data(withJSONObject: runtime)
        try data.write(to: directory.appendingPathComponent("\(pid).json"), options: .atomic)
    }
}
