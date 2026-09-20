import AppKit
import Foundation

struct GhosttyTarget: Sendable {
    let bundleIdentifier: String
    let processIdentifier: pid_t
    let name: String
}

enum GhosttyClientError: LocalizedError {
    case notRunning
    case automationDenied
    case automationFailed(String)

    var errorDescription: String? {
        switch self {
        case .notRunning:
            return "Ghostty is not running."
        case .automationDenied:
            return "Ghostty focus access was denied. Enable Pi Agent Shelf in System Settings → Privacy & Security → Automation."
        case .automationFailed(let message):
            return "Ghostty automation failed: \(message)"
        }
    }
}

final class GhosttyClient {
    private let lock = NSLock()
    private let runScript: (String, [String]) throws -> String
    private var cachedTarget: GhosttyTarget?
    private var terminalIDs: [String: String] = [:]

    init(runScript: @escaping (String, [String]) throws -> String = { source, arguments in
        try ProcessRunner.run(
            "/usr/bin/osascript",
            arguments: ["-e", source] + arguments,
            timeout: 60
        )
    }) {
        self.runScript = runScript
    }

    static func runningTarget() -> GhosttyTarget? {
        let candidates = NSWorkspace.shared.runningApplications.compactMap { application -> (NSRunningApplication, GhosttyTarget)? in
            guard
                let bundleIdentifier = application.bundleIdentifier,
                bundleIdentifier.hasPrefix("com.mitchellh.ghostty"),
                application.executableURL?.lastPathComponent == "ghostty"
            else {
                return nil
            }

            return (
                application,
                GhosttyTarget(
                    bundleIdentifier: bundleIdentifier,
                    processIdentifier: application.processIdentifier,
                    name: application.localizedName ?? "Ghostty"
                )
            )
        }

        return candidates.first(where: { $0.0.isActive })?.1 ?? candidates.first?.1
    }

    func focus(tty: String, target: GhosttyTarget) throws {
        // Focus runs off the UI thread. Serialize requests so a late lookup cannot
        // overwrite a newer cache entry or race a Ghostty process change.
        lock.lock()
        defer { lock.unlock() }

        if cachedTarget?.processIdentifier != target.processIdentifier
            || cachedTarget?.bundleIdentifier != target.bundleIdentifier {
            terminalIDs.removeAll()
            cachedTarget = target
        }

        let cachedID = terminalIDs.removeValue(forKey: tty) ?? ""
        do {
            let terminalID = try runScript(
                Self.focusScript(bundleIdentifier: target.bundleIdentifier),
                [tty, cachedID]
            ).trimmingCharacters(in: .whitespacesAndNewlines)
            guard UUID(uuidString: terminalID) != nil else {
                throw ProcessFailure(executable: "osascript", status: 1, message: "Invalid Ghostty terminal ID.")
            }
            terminalIDs[tty] = terminalID
        } catch let failure as ProcessFailure where failure.status == 1
            && failure.message.contains(String(errAEEventNotPermitted)) {
            throw GhosttyClientError.automationDenied
        } catch {
            // Failed lookups are not cached. Timeouts and permission errors do not retry.
            throw GhosttyClientError.automationFailed(error.localizedDescription)
        }
    }

    static func focusScript(bundleIdentifier: String) -> String {
        let escapedBundleID = bundleIdentifier
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        return #"""
        on run argv
            set targetTTY to item 1 of argv
            set targetID to item 2 of argv
            using terms from application "Ghostty"
                tell application id "\#(escapedBundleID)"
                    if targetID is not "" then
                        try
                            if (get tty of terminal id targetID) is not targetTTY then
                                set targetID to ""
                            end if
                        on error messageText number errorNumber
                            if errorNumber is not -1728 then error messageText number errorNumber
                            set targetID to ""
                        end try
                    end if

                    if targetID is "" then
                        -- Ghostty evaluates this predicate in one Apple Event, not one per terminal.
                        set matchingIDs to get id of every terminal whose tty is targetTTY
                        if (count of matchingIDs) is not 1 then error "Ghostty terminal is no longer available"
                        set targetID to item 1 of matchingIDs
                        -- Revalidate the ID: terminals can close or reorder during the lookup.
                        if (get tty of terminal id targetID) is not targetTTY then
                            error "Ghostty terminal changed during lookup"
                        end if
                    end if

                    ignoring application responses
                        focus terminal id targetID
                    end ignoring
                end tell
            end using terms from
            return targetID
        end run
        """#
    }
}
