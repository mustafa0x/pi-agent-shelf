import Darwin
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

struct ProcessTimeout: LocalizedError {
    let executable: String
    let seconds: TimeInterval

    var errorDescription: String? {
        "\(executable) did not respond within \(Int(seconds)) seconds."
    }
}

private final class DataBox: @unchecked Sendable {
    private let lock = NSLock()
    private var data = Data()

    func set(_ value: Data) {
        lock.lock()
        data = value
        lock.unlock()
    }

    func get() -> Data {
        lock.lock()
        defer { lock.unlock() }
        return data
    }
}

enum ProcessRunner {
    static func run(
        _ executable: String,
        arguments: [String],
        timeout: TimeInterval? = nil
    ) throws -> String {
        let process = Process()
        let outputPipe = Pipe()
        let errorPipe = Pipe()
        let termination = DispatchSemaphore(value: 0)

        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.standardOutput = outputPipe
        process.standardError = errorPipe
        process.terminationHandler = { _ in
            termination.signal()
        }

        try process.run()

        let outputBox = DataBox()
        let errorBox = DataBox()
        let reads = DispatchGroup()
        reads.enter()
        DispatchQueue.global(qos: .utility).async {
            outputBox.set(outputPipe.fileHandleForReading.readDataToEndOfFile())
            reads.leave()
        }
        reads.enter()
        DispatchQueue.global(qos: .utility).async {
            errorBox.set(errorPipe.fileHandleForReading.readDataToEndOfFile())
            reads.leave()
        }

        var didTimeOut = false
        if let timeout {
            didTimeOut = termination.wait(timeout: .now() + timeout) == .timedOut
            if didTimeOut {
                process.terminate()
                if termination.wait(timeout: .now() + 1) == .timedOut {
                    kill(process.processIdentifier, SIGKILL)
                    termination.wait()
                }
            }
        } else {
            termination.wait()
        }

        reads.wait()
        if didTimeOut {
            throw ProcessTimeout(executable: executable, seconds: timeout ?? 0)
        }

        let error = errorBox.get()
        guard process.terminationStatus == 0 else {
            throw ProcessFailure(
                executable: executable,
                status: process.terminationStatus,
                message: String(decoding: error, as: UTF8.self)
            )
        }

        return String(decoding: outputBox.get(), as: UTF8.self)
    }
}
