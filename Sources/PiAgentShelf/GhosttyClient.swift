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

enum GhosttyClient {
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

    static func focus(tty: String, target: GhosttyTarget) throws {
        let escapedTTY = tty
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        let source = #"""
        using terms from application "Ghostty"
            set targetTTY to "\#(escapedTTY)"
            tell application id "\#(target.bundleIdentifier)"
                repeat with terminalRef in terminals
                    if (tty of terminalRef as text) is targetTTY then
                        ignoring application responses
                            focus terminalRef
                        end ignoring
                        return "ok"
                    end if
                end repeat
            end tell
            error "Ghostty terminal is no longer available"
        end using terms from
        """#

        do {
            _ = try ProcessRunner.run(
                "/usr/bin/osascript",
                arguments: ["-e", source],
                timeout: 60
            )
        } catch let failure as ProcessFailure where failure.status == 1
            && failure.message.contains(String(errAEEventNotPermitted)) {
            throw GhosttyClientError.automationDenied
        } catch {
            throw GhosttyClientError.automationFailed(error.localizedDescription)
        }
    }
}
