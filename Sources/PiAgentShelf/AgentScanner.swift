import Foundation

private struct SessionSnapshot {
    let name: String?
    let provider: String?
    let model: String?
    let state: AgentState
}

private struct CachedSessionSnapshot {
    let modifiedAt: Date?
    let fileSize: UInt64?
    let snapshot: SessionSnapshot
}

struct ProcessRecord {
    let pid: Int32
    let parentPID: Int32
    let tty: String
    let command: String
}

final class AgentScanner {
    private let iso8601 = ISO8601DateFormatter()
    private let runtimeDirectory: URL
    private let loadProcesses: () throws -> [ProcessRecord]
    private var sessionCache: [String: CachedSessionSnapshot] = [:]

    init(
        runtimeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".pi/agent/session-runtime", isDirectory: true),
        processTable: (() throws -> [ProcessRecord])? = nil
    ) {
        self.runtimeDirectory = runtimeDirectory
        self.loadProcesses = processTable ?? Self.processTable
    }

    func scan(ghosttyTargets: [GhosttyTarget]) -> ScanResult {
        do {
            let processes = try loadProcesses()
            let processesByPID = Dictionary(uniqueKeysWithValues: processes.map { ($0.pid, $0) })
            let piProcesses = processes.compactMap { process -> (ProcessRecord, GhosttyTarget)? in
                guard
                    URL(fileURLWithPath: process.command).lastPathComponent == "pi",
                    process.tty != "??",
                    let target = ghosttyTargets.first(where: {
                        isDescendant(
                            process.pid,
                            of: Int32($0.processIdentifier),
                            processesByPID: processesByPID
                        )
                    })
                else {
                    return nil
                }
                return (process, target)
            }

            let decoder = JSONDecoder()
            var activeSessionFiles = Set<String>()

            let agents = piProcesses.compactMap { process, target -> PiAgent? in
                let runtimeURL = runtimeDirectory.appendingPathComponent("\(process.pid).json")
                guard
                    let runtimeData = try? Data(contentsOf: runtimeURL),
                    let runtime = try? decoder.decode(RuntimeRecord.self, from: runtimeData),
                    runtime.pid == process.pid
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
                    pid: process.pid,
                    tty: "/dev/\(process.tty)",
                    cwd: runtime.cwd,
                    sessionID: runtime.sessionID,
                    sessionFile: runtime.sessionFile,
                    sessionName: snapshot.name,
                    provider: snapshot.provider,
                    model: snapshot.model,
                    fastMode: FastModeStatus.read(
                        at: runtimeDirectory.appendingPathComponent("\(process.pid).fast.json"),
                        runtime: runtime,
                        provider: snapshot.provider,
                        model: snapshot.model
                    ),
                    ghosttyTarget: target,
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

    private static func processTable() throws -> [ProcessRecord] {
        let output = try ProcessRunner.run("/bin/ps", arguments: ["-axo", "pid=,ppid=,tty=,comm="])

        return output.split(separator: "\n").compactMap { line in
            let fields = line.split(
                maxSplits: 3,
                omittingEmptySubsequences: true,
                whereSeparator: { $0.isWhitespace }
            )
            guard fields.count == 4, let pid = Int32(fields[0]), let parentPID = Int32(fields[1]) else {
                return nil
            }
            return ProcessRecord(
                pid: pid,
                parentPID: parentPID,
                tty: String(fields[2]),
                command: String(fields[3]).trimmingCharacters(in: .whitespaces)
            )
        }
    }

    private func isDescendant(
        _ pid: Int32,
        of ancestorPID: Int32,
        processesByPID: [Int32: ProcessRecord]
    ) -> Bool {
        var currentPID = pid
        var visited = Set<Int32>()

        while let process = processesByPID[currentPID], visited.insert(currentPID).inserted {
            if process.parentPID == ancestorPID {
                return true
            }
            currentPID = process.parentPID
        }

        return false
    }

    private func sessionSnapshot(at url: URL, modifiedAt: Date?, fileSize: UInt64?) -> SessionSnapshot {
        if let cached = sessionCache[url.path],
           cached.modifiedAt == modifiedAt,
           cached.fileSize == fileSize {
            return cached.snapshot
        }

        guard let tail = readTail(of: url, maximumBytes: 1_048_576) else {
            return SessionSnapshot(name: nil, provider: nil, model: nil, state: .unknown)
        }

        var sessionName: String?
        var provider: String?
        var model: String?
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

            if object["type"] as? String == "message",
               let message = object["message"] as? [String: Any],
               let role = message["role"] as? String {
                if role == "assistant" {
                    provider = provider ?? message["provider"] as? String
                    model = model ?? message["model"] as? String
                }

                if state == nil {
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
            }

            if object["type"] as? String == "model_change" {
                provider = provider ?? object["provider"] as? String
                model = model ?? object["modelId"] as? String
            }

            if sessionName != nil, provider != nil, model != nil, state != nil {
                break
            }
        }

        let snapshot = SessionSnapshot(
            name: sessionName,
            provider: provider,
            model: model,
            state: state ?? .idle
        )
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
