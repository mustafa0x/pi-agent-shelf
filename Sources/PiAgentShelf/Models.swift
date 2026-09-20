import Foundation

struct GhosttyTerminal: Sendable {
    let id: String
    let pid: Int32
    let tty: String
    let workingDirectory: String
    let title: String
}

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
    let id: String
    let terminalID: String
    let terminalTitle: String
    let pid: Int32
    let tty: String
    let cwd: String
    let sessionID: String
    let sessionFile: String
    let sessionName: String?
    let lastActivity: Date
    let state: AgentState

    var projectName: String {
        let name = URL(fileURLWithPath: cwd).lastPathComponent
        return name.isEmpty ? cwd : name
    }

    var displayName: String {
        if let sessionName, !sessionName.isEmpty {
            return sessionName
        }
        if !terminalTitle.isEmpty {
            return terminalTitle
        }
        return projectName
    }

    var shortSessionID: String {
        String(sessionID.prefix(8))
    }
}

struct ScanResult: Sendable {
    let agents: [PiAgent]
    let errorMessage: String?
}
