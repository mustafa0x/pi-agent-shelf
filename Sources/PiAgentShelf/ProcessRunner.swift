import Foundation

struct ProcessFailure: LocalizedError {
    let executable: String
    let status: Int32
    let message: String

    var errorDescription: String? {
        let detail = message.trimmingCharacters(in: .whitespacesAndNewlines)
        return detail.isEmpty ? "\(executable) exited with status \(status)" : detail
    }
}

enum ProcessRunner {
    static func run(_ executable: String, arguments: [String]) throws -> String {
        let process = Process()
        let outputPipe = Pipe()
        let errorPipe = Pipe()

        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.standardOutput = outputPipe
        process.standardError = errorPipe

        try process.run()
        let output = outputPipe.fileHandleForReading.readDataToEndOfFile()
        let error = errorPipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()

        guard process.terminationStatus == 0 else {
            throw ProcessFailure(
                executable: executable,
                status: process.terminationStatus,
                message: String(decoding: error, as: UTF8.self)
            )
        }

        return String(decoding: output, as: UTF8.self)
    }
}
