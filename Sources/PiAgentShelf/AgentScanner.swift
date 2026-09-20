import Foundation

private struct SessionSnapshot {
    let name: String?
    let state: AgentState
}

private struct CachedSessionSnapshot {
    let modifiedAt: Date?
    let fileSize: UInt64?
    let snapshot: SessionSnapshot
}

final class AgentScanner {
    private let iso8601 = ISO8601DateFormatter()
    private var sessionCache: [String: CachedSessionSnapshot] = [:]

    func scan() -> ScanResult {
        do {
            let terminals = try GhosttyClient.terminals()
            let piProcesses = try livePiProcessesByTTY()
            let runtimeDirectory = FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent(".pi/agent/session-runtime", isDirectory: true)
            let decoder = JSONDecoder()

            var activeSessionFiles = Set<String>()
            let agents = terminals.compactMap { terminal -> PiAgent? in
                let normalizedTTY = normalizeTTY(terminal.tty)
                guard let pid = piProcesses[normalizedTTY] else {
                    return nil
                }

                let runtimeURL = runtimeDirectory.appendingPathComponent("\(pid).json")
                guard
                    let runtimeData = try? Data(contentsOf: runtimeURL),
                    let runtime = try? decoder.decode(RuntimeRecord.self, from: runtimeData),
                    runtime.pid == pid
                else {
                    return nil
                }

                activeSessionFiles.insert(runtime.sessionFile)
                let sessionURL = URL(fileURLWithPath: runtime.sessionFile)
                let attributes = try? FileManager.default.attributesOfItem(atPath: sessionURL.path)
                let modifiedAt = attributes?[.modificationDate] as? Date
                let fileSize = (attributes?[.size] as? NSNumber)?.uint64Value
                let fallbackDate = iso8601.date(from: runtime.updatedAt) ?? .distantPast
                let snapshot = sessionSnapshot(at: sessionURL, modifiedAt: modifiedAt, fileSize: fileSize)

                return PiAgent(
                    id: terminal.id,
                    terminalID: terminal.id,
                    terminalTitle: terminal.title,
                    pid: pid,
                    tty: terminal.tty,
                    cwd: runtime.cwd,
                    sessionID: runtime.sessionID,
                    sessionFile: runtime.sessionFile,
                    sessionName: snapshot.name,
                    lastActivity: modifiedAt ?? fallbackDate,
                    state: snapshot.state
                )
            }
            .sorted {
                if $0.lastActivity == $1.lastActivity {
                    return $0.displayName.localizedStandardCompare($1.displayName) == .orderedAscending
                }
                return $0.lastActivity > $1.lastActivity
            }

            sessionCache = sessionCache.filter { activeSessionFiles.contains($0.key) }
            return ScanResult(agents: agents, errorMessage: nil)
        } catch {
            return ScanResult(agents: [], errorMessage: error.localizedDescription)
        }
    }

    private func livePiProcessesByTTY() throws -> [String: Int32] {
        let output = try ProcessRunner.run("/bin/ps", arguments: ["-axo", "pid=,tty=,comm="])
        var result: [String: Int32] = [:]

        for line in output.split(separator: "\n") {
            let fields = line.split(
                maxSplits: 2,
                omittingEmptySubsequences: true,
                whereSeparator: { $0.isWhitespace }
            )
            guard
                fields.count == 3,
                let pid = Int32(fields[0]),
                URL(
                    fileURLWithPath: String(fields[2]).trimmingCharacters(in: .whitespaces)
                ).lastPathComponent == "pi"
            else {
                continue
            }
            result[normalizeTTY(String(fields[1]))] = pid
        }

        return result
    }

    private func normalizeTTY(_ tty: String) -> String {
        URL(fileURLWithPath: tty).lastPathComponent
    }

    private func sessionSnapshot(at url: URL, modifiedAt: Date?, fileSize: UInt64?) -> SessionSnapshot {
        if let cached = sessionCache[url.path],
           cached.modifiedAt == modifiedAt,
           cached.fileSize == fileSize {
            return cached.snapshot
        }

        guard let tail = readTail(of: url, maximumBytes: 1_048_576) else {
            return SessionSnapshot(name: nil, state: .unknown)
        }

        var sessionName: String?
        var state: AgentState?

        for line in tail.split(separator: "\n").reversed() {
            guard
                let data = String(line).data(using: .utf8),
                let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
            else {
                continue
            }

            if sessionName == nil, object["type"] as? String == "session_info" {
                sessionName = object["name"] as? String
            }

            if state == nil,
               object["type"] as? String == "message",
               let message = object["message"] as? [String: Any],
               let role = message["role"] as? String {
                switch role {
                case "assistant":
                    state = message["stopReason"] as? String == "toolUse" ? .working : .idle
                case "user", "toolResult":
                    state = .working
                case "bashExecution":
                    state = .idle
                default:
                    break
                }
            }

            if sessionName != nil, state != nil {
                break
            }
        }

        let snapshot = SessionSnapshot(name: sessionName, state: state ?? .idle)
        sessionCache[url.path] = CachedSessionSnapshot(
            modifiedAt: modifiedAt,
            fileSize: fileSize,
            snapshot: snapshot
        )
        return snapshot
    }

    private func readTail(of url: URL, maximumBytes: UInt64) -> String? {
        guard let handle = try? FileHandle(forReadingFrom: url) else {
            return nil
        }
        defer { try? handle.close() }

        guard let size = try? handle.seekToEnd() else {
            return nil
        }
        let offset = size > maximumBytes ? size - maximumBytes : 0
        do {
            try handle.seek(toOffset: offset)
            let data = try handle.readToEnd() ?? Data()
            return String(decoding: data, as: UTF8.self)
        } catch {
            return nil
        }
    }
}
