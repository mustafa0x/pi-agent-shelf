import Foundation

private let ghosttyQueryScript = #"""
set fieldSeparator to ASCII character 31
set recordSeparator to ASCII character 30
set output to ""

tell application "Ghostty"
    repeat with terminalRef in terminals
        set terminalDirectory to ""
        set terminalTitle to ""
        try
            set terminalDirectory to working directory of terminalRef as text
        end try
        try
            set terminalTitle to name of terminalRef as text
        end try
        set output to output & (id of terminalRef as text) & fieldSeparator & (pid of terminalRef as text) & fieldSeparator & (tty of terminalRef as text) & fieldSeparator & terminalDirectory & fieldSeparator & terminalTitle & recordSeparator
    end repeat
end tell

return output
"""#

private let ghosttyFocusScript = #"""
on run argv
    set targetID to item 1 of argv
    tell application "Ghostty"
        repeat with terminalRef in terminals
            if (id of terminalRef as text) is targetID then
                focus terminalRef
                return "ok"
            end if
        end repeat
    end tell
    error "Ghostty terminal is no longer available"
end run
"""#

enum GhosttyClient {
    static func terminals() throws -> [GhosttyTerminal] {
        let output = try ProcessRunner.run("/usr/bin/osascript", arguments: ["-e", ghosttyQueryScript])
        let recordSeparator = Character(UnicodeScalar(30))
        let fieldSeparator = Character(UnicodeScalar(31))

        return output.split(separator: recordSeparator).compactMap { record in
            let fields = record.split(separator: fieldSeparator, omittingEmptySubsequences: false)
            guard fields.count == 5, let pid = Int32(fields[1]) else {
                return nil
            }
            return GhosttyTerminal(
                id: String(fields[0]),
                pid: pid,
                tty: String(fields[2]),
                workingDirectory: String(fields[3]),
                title: String(fields[4])
            )
        }
    }

    static func focus(terminalID: String) throws {
        _ = try ProcessRunner.run(
            "/usr/bin/osascript",
            arguments: ["-e", ghosttyFocusScript, terminalID]
        )
    }
}
