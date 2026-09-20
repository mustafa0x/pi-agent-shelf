import Foundation

struct RuntimeRecord: Decodable, Sendable {
    let pid: Int32
    let sessionID: String
    let sessionFile: String
    let cwd: String
    let updatedAt: String

    enum CodingKeys: String, CodingKey {
        case pid
        case sessionID = "session_id"
        case sessionFile = "session_file"
        case cwd
        case updatedAt = "updated_at"
    }
}

enum AgentState: String, Sendable {
    case working = "Working"
    case idle = "Idle"
    case unknown = "Unknown"
}

struct PiAgent: Identifiable, Sendable {
    let pid: Int32
    let tty: String
    let cwd: String
    let sessionID: String
    let sessionFile: String
    let sessionName: String?
    let provider: String?
    let model: String?
    let fastMode: Bool?
    let lastActivity: Date
    let state: AgentState

    var id: String { sessionID }

    var projectName: String {
        let name = URL(fileURLWithPath: cwd).lastPathComponent
        return name.isEmpty ? cwd : name
    }

    var displayName: String {
        if let sessionName, !sessionName.isEmpty {
            return sessionName
        }
        return projectName
    }

    var fastModeDescription: String {
        guard let fastMode else { return "Fast mode unknown" }
        return fastMode ? "Fast mode on" : "Fast mode off"
    }

    var shortSessionID: String {
        String(sessionID.prefix(8))
    }

    var displayCWD: String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        guard cwd == home || cwd.hasPrefix("\(home)/") else { return cwd }
        return "~\(cwd.dropFirst(home.count))"
    }
}

struct ScanResult: Sendable {
    let agents: [PiAgent]
    let errorMessage: String?
}
