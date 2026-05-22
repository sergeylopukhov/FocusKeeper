import Foundation

public final class FocusKeeperLogger: @unchecked Sendable {
    public static let shared = FocusKeeperLogger()

    private let lock = NSLock()
    private let fileManager: FileManager
    private let logURL: URL
    private let formatter: ISO8601DateFormatter

    public convenience init() {
        let homeDirectory = FileManager.default.homeDirectoryForCurrentUser
        self.init(
            logURL: homeDirectory
                .appendingPathComponent("Library")
                .appendingPathComponent("Logs")
                .appendingPathComponent("FocusKeeper.log")
        )
    }

    init(logURL: URL, fileManager: FileManager = .default) {
        self.logURL = logURL
        self.fileManager = fileManager
        self.formatter = ISO8601DateFormatter()
        self.formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    }

    public func info(_ message: String) {
        write(level: "INFO", message: message)
    }

    public func error(_ message: String) {
        write(level: "ERROR", message: message)
    }

    public func log(_ error: Error, context: String) {
        let message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription

        switch error {
        case FocusBackendError.permissionDenied:
            write(level: "ERROR", message: "\(context): permission error: \(message)")
        case FocusBackendError.invalidJSON, FocusBackendError.invalidStructure:
            write(level: "ERROR", message: "\(context): JSON error: \(message)")
        default:
            write(level: "ERROR", message: "\(context): \(message)")
        }
    }

    private func write(level: String, message: String) {
        lock.lock()
        defer { lock.unlock() }

        let line = "\(formatter.string(from: Date())) [\(level)] \(message)\n"

        do {
            try fileManager.createDirectory(
                at: logURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )

            if !fileManager.fileExists(atPath: logURL.path) {
                try Data().write(to: logURL)
            }

            let handle = try FileHandle(forWritingTo: logURL)
            try handle.seekToEnd()
            try handle.write(contentsOf: Data(line.utf8))
            try handle.close()
        } catch {
            NSLog("FocusKeeper logging failed: \(error.localizedDescription)")
        }
    }
}
