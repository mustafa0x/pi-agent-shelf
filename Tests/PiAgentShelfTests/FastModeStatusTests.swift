import XCTest
@testable import PiAgentShelf

final class FastModeStatusTests: XCTestCase {
    private var directory: URL!
    private var statusURL: URL { directory.appendingPathComponent("123.fast.json") }
    private let runtime = RuntimeRecord(
        pid: 123, sessionID: "session-a", sessionFile: "/tmp/a.jsonl", cwd: "/tmp", updatedAt: ""
    )

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try FileManager.default.removeItem(at: directory)
    }

    private func writeStatus(
        enabled: Bool = true, pid: Int = 123, sessionID: String = "session-a",
        sessionFile: String = "/tmp/a.jsonl", provider: String = "openai-codex", model: String = "gpt-5.6"
    ) throws {
        let data = try JSONSerialization.data(withJSONObject: [
            "pid": pid, "session_id": sessionID, "session_file": sessionFile,
            "provider": provider, "model": model, "enabled": enabled
        ])
        try data.write(to: statusURL, options: .atomic)
    }

    private func readStatus() -> Bool? {
        FastModeStatus.read(at: statusURL, runtime: runtime, provider: "openai-codex", model: "gpt-5.6")
    }

    func testReflectsToggleWithoutSessionFileChanges() throws {
        try writeStatus()
        XCTAssertEqual(readStatus(), true)
        try writeStatus(enabled: false)
        XCTAssertEqual(readStatus(), false)
        try writeStatus()
        XCTAssertEqual(readStatus(), true)
    }

    func testMissingAndMalformedReportsAreUnknownNotOff() throws {
        XCTAssertNil(readStatus())
        try Data("{bad json".utf8).write(to: statusURL)
        XCTAssertNil(readStatus())
        try Data("{}".utf8).write(to: statusURL)
        XCTAssertNil(readStatus())
    }

    func testRejectsReportFromOtherProcessOrSession() throws {
        try writeStatus(pid: 456)
        XCTAssertNil(readStatus())
        try writeStatus(sessionID: "session-b")
        XCTAssertNil(readStatus())
        try writeStatus(sessionFile: "/tmp/b.jsonl")
        XCTAssertNil(readStatus())
    }

    func testRejectsReportForDifferentOrUnknownModel() throws {
        try writeStatus(provider: "openai")
        XCTAssertNil(readStatus())
        try writeStatus(model: "gpt-6-astra")
        XCTAssertNil(readStatus())
        try writeStatus()
        XCTAssertNil(FastModeStatus.read(at: statusURL, runtime: runtime, provider: nil, model: nil))
    }
}
