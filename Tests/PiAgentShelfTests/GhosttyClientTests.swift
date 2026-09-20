import XCTest
@testable import PiAgentShelf

final class GhosttyClientTests: XCTestCase {
    private let target = GhosttyTarget(
        bundleIdentifier: "com.mitchellh.ghostty.diagnostics",
        processIdentifier: 100,
        name: "Ghostty"
    )
    private let firstID = "00000000-0000-0000-0000-000000000001"
    private let secondID = "00000000-0000-0000-0000-000000000002"

    func testCacheIsLazyAndReusesSuccessfulIDsPerTTY() throws {
        var calls: [[String]] = []
        let client = GhosttyClient { _, arguments in
            calls.append(arguments)
            return arguments[0] == "/dev/ttys001" ? self.firstID + "\n" : self.secondID
        }
        XCTAssertTrue(calls.isEmpty, "Discovery must not trigger Automation")

        try client.focus(tty: "/dev/ttys001", target: target)
        try client.focus(tty: "/dev/ttys002", target: target)
        try client.focus(tty: "/dev/ttys001", target: target)
        try client.focus(tty: "/dev/ttys002", target: target)

        XCTAssertEqual(calls, [
            ["/dev/ttys001", ""], ["/dev/ttys002", ""],
            ["/dev/ttys001", firstID], ["/dev/ttys002", secondID]
        ])
    }

    func testRefreshedIDReplacesStaleEntry() throws {
        var calls: [[String]] = []
        let client = GhosttyClient { _, arguments in
            calls.append(arguments)
            // The script returns a replacement ID after rejecting a stale cached ID.
            return calls.count == 1 ? self.firstID : self.secondID
        }
        for _ in 0..<3 {
            try client.focus(tty: "/dev/ttys001", target: target)
        }
        XCTAssertEqual(calls.map { $0[1] }, ["", firstID, secondID])
    }

    func testProcessRestartAndBundleChangeInvalidateCache() throws {
        var calls: [[String]] = []
        let client = GhosttyClient { _, arguments in
            calls.append(arguments)
            return self.firstID
        }
        try client.focus(tty: "/dev/ttys001", target: target)
        let restarted = GhosttyTarget(
            bundleIdentifier: target.bundleIdentifier, processIdentifier: 101, name: target.name
        )
        try client.focus(tty: "/dev/ttys001", target: restarted)
        try client.focus(tty: "/dev/ttys001", target: restarted)
        let otherBundle = GhosttyTarget(
            bundleIdentifier: "com.mitchellh.ghostty", processIdentifier: 101, name: target.name
        )
        try client.focus(tty: "/dev/ttys001", target: otherBundle)
        XCTAssertEqual(calls.map { $0[1] }, ["", "", firstID, ""])
    }

    func testTimeoutEvictsOnlyFailedTTYWithoutRetrying() throws {
        var calls: [[String]] = []
        let client = GhosttyClient { _, arguments in
            calls.append(arguments)
            if calls.count == 3 { throw ProcessTimeout(executable: "osascript", seconds: 60) }
            return arguments[0] == "/dev/ttys001" ? self.firstID : self.secondID
        }
        try client.focus(tty: "/dev/ttys001", target: target)
        try client.focus(tty: "/dev/ttys002", target: target)
        XCTAssertThrowsError(try client.focus(tty: "/dev/ttys001", target: target)) { error in
            guard case GhosttyClientError.automationFailed(let message) = error else {
                return XCTFail("Unexpected error: \(error)")
            }
            XCTAssertTrue(message.contains("60 seconds"))
        }
        XCTAssertEqual(calls.count, 3, "A timeout must not trigger another Automation request")
        try client.focus(tty: "/dev/ttys001", target: target)
        try client.focus(tty: "/dev/ttys002", target: target)
        XCTAssertEqual(calls[3], ["/dev/ttys001", ""])
        XCTAssertEqual(calls[4], ["/dev/ttys002", secondID])
    }

    func testAutomationDenialDoesNotRetry() {
        var calls = 0
        let client = GhosttyClient { _, _ in
            calls += 1
            throw ProcessFailure(executable: "osascript", status: 1, message: "Not authorized (-1743)")
        }
        XCTAssertThrowsError(try client.focus(tty: "/dev/ttys001", target: target)) { error in
            guard case GhosttyClientError.automationDenied = error else {
                return XCTFail("Unexpected error: \(error)")
            }
        }
        XCTAssertEqual(calls, 1)
    }

    func testMalformedOutputIsNotCached() throws {
        var calls: [[String]] = []
        let client = GhosttyClient { _, arguments in
            calls.append(arguments)
            return calls.count == 1 ? "ok" : self.firstID
        }
        XCTAssertThrowsError(try client.focus(tty: "/dev/ttys001", target: target))
        try client.focus(tty: "/dev/ttys001", target: target)
        XCTAssertEqual(calls.map { $0[1] }, ["", ""])
    }

    func testScriptUsesIDValidationAndSingleServerSideLookup() {
        let script = GhosttyClient.focusScript(bundleIdentifier: target.bundleIdentifier)
        XCTAssertTrue(script.contains("tty of terminal id targetID"))
        XCTAssertTrue(script.contains("if errorNumber is not -1728 then error"))
        XCTAssertTrue(script.contains("id of every terminal whose tty is targetTTY"))
        XCTAssertTrue(script.contains("focus terminal id targetID"))
        XCTAssertFalse(script.contains("repeat"), "No per-terminal IPC loop or unbounded retry")
    }
}
