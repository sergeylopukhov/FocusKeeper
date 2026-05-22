import Foundation

public enum FocusStatus: String, Sendable {
    case enabled
    case disabled
    case unknown
}

public enum FocusBackendError: Error, LocalizedError, Sendable {
    case missingAssertionsFile(URL)
    case permissionDenied(URL)
    case invalidJSON(URL)
    case invalidStructure(String)
    case backupFailed(String)
    case writeFailed(String)
    case restartFailed(process: String, reason: String)

    public var errorDescription: String? {
        switch self {
        case .missingAssertionsFile(let url):
            return "Focus assertions file does not exist at \(url.path)."
        case .permissionDenied(let url):
            return "Permission denied while accessing \(url.path). FocusKeeper needs Full Disk Access."
        case .invalidJSON(let url):
            return "Focus assertions file contains invalid JSON at \(url.path)."
        case .invalidStructure(let message):
            return "Focus assertions file has an unsupported structure: \(message)"
        case .backupFailed(let message):
            return "Could not create Focus assertions backup: \(message)"
        case .writeFailed(let message):
            return "Could not write Focus assertions file: \(message)"
        case .restartFailed(let process, let reason):
            return "Could not restart \(process): \(reason)"
        }
    }
}

public struct FocusAssertionSnapshot: Sendable {
    public let recordsJSONData: Data
    public let isEmpty: Bool

    public init(recordsJSONData: Data, isEmpty: Bool) {
        self.recordsJSONData = recordsJSONData
        self.isEmpty = isEmpty
    }
}

public final class FocusBackend: @unchecked Sendable {
    private static let backupSessionState = BackupSessionState()

    private let fileManager: FileManager
    private let assertionsURL: URL
    private let backupsDirectoryURL: URL
    private let dateProvider: @Sendable () -> Date
    private let uuidProvider: @Sendable () -> UUID
    private let logger: FocusKeeperLogger

    public convenience init() {
        let homeDirectory = FileManager.default.homeDirectoryForCurrentUser
        self.init(
            assertionsURL: homeDirectory
                .appendingPathComponent("Library")
                .appendingPathComponent("DoNotDisturb")
                .appendingPathComponent("DB")
                .appendingPathComponent("Assertions.json"),
            backupsDirectoryURL: homeDirectory
                .appendingPathComponent("Library")
                .appendingPathComponent("Application Support")
                .appendingPathComponent("FocusKeeper")
                .appendingPathComponent("Backups")
        )
    }

    public init(
        assertionsURL: URL,
        backupsDirectoryURL: URL,
        fileManager: FileManager = .default,
        dateProvider: @escaping @Sendable () -> Date = Date.init,
        uuidProvider: @escaping @Sendable () -> UUID = UUID.init,
        logger: FocusKeeperLogger = .shared
    ) {
        self.assertionsURL = assertionsURL
        self.backupsDirectoryURL = backupsDirectoryURL
        self.fileManager = fileManager
        self.dateProvider = dateProvider
        self.uuidProvider = uuidProvider
        self.logger = logger
    }

    public func enableFocus(modeIdentifier: String) throws {
        var root = try loadRootObject()
        let currentStatus = try status(from: root, modeIdentifier: modeIdentifier)

        logger.info("backend enable requested; modeIdentifier=\(modeIdentifier); actual status=\(currentStatus.rawValue)")

        guard currentStatus != .enabled else {
            logger.info("backend enable skipped; modeIdentifier=\(modeIdentifier) is already active")
            return
        }

        let appleTimestamp = currentAppleAbsoluteTime()

        try updateHeaderTimestamp(in: &root, timestamp: appleTimestamp)
        try setStoreAssertionRecords(
            in: &root,
            records: [makeFocusAssertionRecord(modeIdentifier: modeIdentifier, timestamp: appleTimestamp)]
        )

        try writeRootObject(root)
        try restart(processNames: ["donotdisturbd", "NotificationCenter"])
        logger.info("backend enable completed")
    }

    public func disableWorkFocus() throws {
        var root = try loadRootObject()
        let records = try storeAssertionRecords(from: root)
        let currentStatus = status(from: records, modeIdentifier: "any")

        logger.info("backend disable requested; actual status=\(currentStatus.rawValue); assertion records=\(records.count)")

        guard !records.isEmpty else {
            logger.info("backend disable skipped; storeAssertionRecords is already empty")
            return
        }

        try updateHeaderTimestamp(in: &root, timestamp: currentAppleAbsoluteTime())
        try setStoreAssertionRecords(in: &root, records: [])

        try writeRootObject(root)
        try restart(processNames: ["donotdisturbd", "usernotificationsd", "usernoted"])
        logger.info("backend disable completed")
    }

    public func getStatus(modeIdentifier: String) throws -> FocusStatus {
        let root = try loadRootObject()
        return try status(from: root, modeIdentifier: modeIdentifier)
    }

    public func captureAssertionSnapshot() throws -> FocusAssertionSnapshot {
        let root = try loadRootObject()
        let records = try storeAssertionRecords(from: root)
        let data = try serializedRecords(records)
        logger.info("backend captured Focus assertion snapshot; assertion records=\(records.count)")
        return FocusAssertionSnapshot(recordsJSONData: data, isEmpty: records.isEmpty)
    }

    public func restoreAssertionSnapshot(_ snapshot: FocusAssertionSnapshot) throws {
        let restoredRecords = try records(fromSnapshot: snapshot)
        var root = try loadRootObject()
        let currentRecords = try storeAssertionRecords(from: root)

        logger.info(
            "backend restore snapshot requested; restored records=\(restoredRecords.count); current records=\(currentRecords.count)"
        )

        if try serializedRecords(currentRecords) == snapshot.recordsJSONData {
            logger.info("backend restore snapshot skipped; current records already match snapshot")
            return
        }

        try updateHeaderTimestamp(in: &root, timestamp: currentAppleAbsoluteTime())
        try setStoreAssertionRecords(in: &root, records: restoredRecords)
        try writeRootObject(root)

        if restoredRecords.isEmpty {
            try restart(processNames: ["donotdisturbd", "usernotificationsd", "usernoted"])
        } else {
            try restart(processNames: ["donotdisturbd", "NotificationCenter"])
        }

        logger.info("backend restore snapshot completed")
    }
}

private extension FocusBackend {
    var appleAbsoluteTimeOffset: TimeInterval {
        978_307_200
    }

    func status(from root: [String: Any], modeIdentifier: String) throws -> FocusStatus {
        status(from: try storeAssertionRecords(from: root), modeIdentifier: modeIdentifier)
    }

    func status(from records: [[String: Any]], modeIdentifier: String) -> FocusStatus {
        guard !records.isEmpty else {
            return .disabled
        }

        let hasWorkFocusRecord = records.contains { record in
            guard
                let details = record["assertionDetails"] as? [String: Any],
                let recordModeIdentifier = details["assertionDetailsModeIdentifier"] as? String
            else {
                return false
            }

            return recordModeIdentifier == modeIdentifier
        }

        return hasWorkFocusRecord ? .enabled : .unknown
    }

    func currentAppleAbsoluteTime() -> TimeInterval {
        dateProvider().timeIntervalSince1970 - appleAbsoluteTimeOffset
    }

    func loadRootObject() throws -> [String: Any] {
        guard fileManager.fileExists(atPath: assertionsURL.path) else {
            throw FocusBackendError.missingAssertionsFile(assertionsURL)
        }

        let data: Data
        do {
            data = try Data(contentsOf: assertionsURL)
        } catch {
            let mappedError = mapFileAccessError(error, url: assertionsURL)
            logger.log(mappedError, context: "backend read")
            throw mappedError
        }

        do {
            guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                throw FocusBackendError.invalidStructure("top-level JSON value is not an object")
            }

            return root
        } catch let backendError as FocusBackendError {
            logger.log(backendError, context: "backend parse")
            throw backendError
        } catch {
            let mappedError = FocusBackendError.invalidJSON(assertionsURL)
            logger.log(mappedError, context: "backend parse")
            throw mappedError
        }
    }

    func updateHeaderTimestamp(in root: inout [String: Any], timestamp: TimeInterval) throws {
        var header = root["header"] as? [String: Any] ?? [:]
        header["timestamp"] = timestamp
        root["header"] = header
    }

    func storeAssertionRecords(from root: [String: Any]) throws -> [[String: Any]] {
        guard let data = root["data"] as? [Any] else {
            throw FocusBackendError.invalidStructure("missing data array")
        }

        guard let firstDataItem = data.first as? [String: Any] else {
            throw FocusBackendError.invalidStructure("data[0] is missing or is not an object")
        }

        guard let records = firstDataItem["storeAssertionRecords"] as? [Any] else {
            return []
        }

        return records.compactMap { $0 as? [String: Any] }
    }

    func serializedRecords(_ records: [[String: Any]]) throws -> Data {
        guard JSONSerialization.isValidJSONObject(records) else {
            throw FocusBackendError.invalidStructure("storeAssertionRecords cannot be serialized as JSON")
        }

        do {
            return try JSONSerialization.data(withJSONObject: records, options: [.sortedKeys])
        } catch {
            throw FocusBackendError.invalidJSON(assertionsURL)
        }
    }

    func records(fromSnapshot snapshot: FocusAssertionSnapshot) throws -> [[String: Any]] {
        do {
            guard let records = try JSONSerialization.jsonObject(with: snapshot.recordsJSONData) as? [[String: Any]] else {
                throw FocusBackendError.invalidStructure("saved Focus assertion snapshot is not an array of objects")
            }

            return records
        } catch let backendError as FocusBackendError {
            throw backendError
        } catch {
            throw FocusBackendError.invalidStructure("saved Focus assertion snapshot contains invalid JSON")
        }
    }

    func setStoreAssertionRecords(in root: inout [String: Any], records: [[String: Any]]) throws {
        guard var data = root["data"] as? [Any] else {
            throw FocusBackendError.invalidStructure("missing data array")
        }

        guard !data.isEmpty else {
            throw FocusBackendError.invalidStructure("data array is empty")
        }

        guard var firstDataItem = data[0] as? [String: Any] else {
            throw FocusBackendError.invalidStructure("data[0] is not an object")
        }

        firstDataItem["storeAssertionRecords"] = records
        data[0] = firstDataItem
        root["data"] = data
    }

    func makeFocusAssertionRecord(modeIdentifier: String, timestamp: TimeInterval) -> [String: Any] {
        [
            "assertionUUID": uuidProvider().uuidString.uppercased(),
            "assertionSource": [
                "assertionClientIdentifier": "com.apple.focus.activity-manager"
            ],
            "assertionStartDateTimestamp": timestamp,
            "assertionDetails": [
                "assertionDetailsIdentifier": "com.apple.focus.activity-manager",
                "assertionDetailsModeIdentifier": modeIdentifier,
                "assertionDetailsLifetime": [
                    "assertionDetailsScheduleLifetimeScheduleIdentifier": "com.apple.donotdisturb.schedule.default",
                    "assertionDetailsLifetimeType": "schedule",
                    "assertionDetailsScheduleLifetimeBehavior": "expire-on-end"
                ],
                "assertionDetailsReason": "user-action"
            ]
        ]
    }

    func writeRootObject(_ root: [String: Any]) throws {
        guard JSONSerialization.isValidJSONObject(root) else {
            throw FocusBackendError.invalidStructure("updated object cannot be serialized as JSON")
        }

        try createBackupIfNeeded()

        let data: Data
        do {
            data = try JSONSerialization.data(withJSONObject: root, options: [.prettyPrinted, .sortedKeys])
        } catch {
            throw FocusBackendError.writeFailed(error.localizedDescription)
        }

        try atomicReplaceOriginal(with: data)
        logger.info("backend wrote Assertions.json atomically")
    }

    func createBackupIfNeeded() throws {
        try Self.backupSessionState.runOnce {
            do {
                try fileManager.createDirectory(
                    at: backupsDirectoryURL,
                    withIntermediateDirectories: true
                )

                let backupURL = backupsDirectoryURL.appendingPathComponent(
                    "Assertions-\(backupTimestamp()).json"
                )
                try fileManager.copyItem(at: assertionsURL, to: backupURL)
            } catch {
                throw FocusBackendError.backupFailed(error.localizedDescription)
            }
        }
    }

    final class BackupSessionState: @unchecked Sendable {
        private let lock = NSLock()
        private var didRun = false

        func runOnce(_ operation: () throws -> Void) throws {
            lock.lock()
            defer { lock.unlock() }

            guard !didRun else {
                return
            }

            try operation()
            didRun = true
        }
    }

    func backupTimestamp() -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        return formatter.string(from: dateProvider())
    }

    func atomicReplaceOriginal(with data: Data) throws {
        let directoryURL = assertionsURL.deletingLastPathComponent()
        let temporaryURL = directoryURL.appendingPathComponent(
            ".Assertions.json.FocusKeeper.\(UUID().uuidString).tmp"
        )

        do {
            try data.write(to: temporaryURL, options: [])
            try copyFileAttributes(from: assertionsURL, to: temporaryURL)
            _ = try fileManager.replaceItemAt(
                assertionsURL,
                withItemAt: temporaryURL,
                backupItemName: nil,
                options: []
            )
        } catch {
            try? fileManager.removeItem(at: temporaryURL)
            let mappedError = mapWriteError(error)
            logger.log(mappedError, context: "backend write")
            throw mappedError
        }
    }

    func copyFileAttributes(from sourceURL: URL, to destinationURL: URL) throws {
        let attributes = try fileManager.attributesOfItem(atPath: sourceURL.path)
        var copiedAttributes: [FileAttributeKey: Any] = [:]

        for key in [FileAttributeKey.posixPermissions, .ownerAccountID, .groupOwnerAccountID] {
            if let value = attributes[key] {
                copiedAttributes[key] = value
            }
        }

        if !copiedAttributes.isEmpty {
            try fileManager.setAttributes(copiedAttributes, ofItemAtPath: destinationURL.path)
        }
    }

    func restart(processNames: [String]) throws {
        for processName in processNames {
            logger.info("backend restarting process: \(processName)")
            try runKillall(processName)
        }
    }

    func runKillall(_ processName: String) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/killall")
        process.arguments = [processName]

        let outputPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = outputPipe

        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            throw FocusBackendError.restartFailed(
                process: processName,
                reason: error.localizedDescription
            )
        }

        if process.terminationStatus != 0 && process.terminationStatus != 1 {
            let output = String(
                data: outputPipe.fileHandleForReading.readDataToEndOfFile(),
                encoding: .utf8
            )?.trimmingCharacters(in: .whitespacesAndNewlines)

            throw FocusBackendError.restartFailed(
                process: processName,
                reason: output?.isEmpty == false ? output! : "exit code \(process.terminationStatus)"
            )
        }
    }

    func mapFileAccessError(_ error: Error, url: URL) -> FocusBackendError {
        let nsError = error as NSError
        if nsError.domain == NSCocoaErrorDomain {
            switch nsError.code {
            case NSFileReadNoPermissionError, NSFileReadNoSuchFileError:
                if nsError.code == NSFileReadNoSuchFileError {
                    return .missingAssertionsFile(url)
                }

                return .permissionDenied(url)
            default:
                break
            }
        }

        if nsError.domain == NSPOSIXErrorDomain && nsError.code == Int(EACCES) {
            return .permissionDenied(url)
        }

        return .invalidJSON(url)
    }

    func mapWriteError(_ error: Error) -> FocusBackendError {
        let nsError = error as NSError
        if nsError.domain == NSCocoaErrorDomain {
            switch nsError.code {
            case NSFileWriteNoPermissionError, NSFileNoSuchFileError:
                if nsError.code == NSFileNoSuchFileError {
                    return .missingAssertionsFile(assertionsURL)
                }

                return .permissionDenied(assertionsURL)
            default:
                break
            }
        }

        if nsError.domain == NSPOSIXErrorDomain && nsError.code == Int(EACCES) {
            return .permissionDenied(assertionsURL)
        }

        return .writeFailed(error.localizedDescription)
    }
}
