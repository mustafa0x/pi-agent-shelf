import Foundation

/// Written by the Fast extension from its live state, never inferred from shared config.
struct FastModeStatus: Decodable {
    let pid: Int32
    let sessionID: String
    let sessionFile: String
    let provider: String
    let model: String
    let enabled: Bool

    enum CodingKeys: String, CodingKey {
        case pid, provider, model, enabled
        case sessionID = "session_id"
        case sessionFile = "session_file"
    }

    static func read(at url: URL, runtime: RuntimeRecord, provider: String?, model: String?) -> Bool? {
        guard
            let data = try? Data(contentsOf: url),
            let status = try? JSONDecoder().decode(Self.self, from: data),
            status.pid == runtime.pid,
            status.sessionID == runtime.sessionID,
            status.sessionFile == runtime.sessionFile,
            status.provider == provider,
            status.model == model
        else {
            return nil
        }
        return status.enabled
    }
}
