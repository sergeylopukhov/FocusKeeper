import AppKit
import FocusBackend
import Foundation

enum FullDiskAccessStatus: Equatable {
    case allowed
    case denied(String)
    case unknown(String)

    var needsUserAction: Bool {
        switch self {
        case .allowed:
            return false
        case .denied, .unknown:
            return true
        }
    }

    var menuTitle: String {
        switch self {
        case .allowed:
            return "Доступ: Full Disk Access есть"
        case .denied:
            return "Доступ: нужен Full Disk Access"
        case .unknown:
            return "Доступ: неизвестно"
        }
    }

    var message: String {
        switch self {
        case .allowed:
            return "FocusKeeper can read the macOS Focus assertions file."
        case .denied(let message), .unknown(let message):
            return message
        }
    }
}

@MainActor
final class FullDiskAccessChecker: ObservableObject {
    @Published private(set) var status: FullDiskAccessStatus = .unknown("Permissions have not been checked yet.")

    private let assertionsURL: URL
    private let logger = FocusKeeperLogger.shared

    init() {
        let homeDirectory = FileManager.default.homeDirectoryForCurrentUser
        self.assertionsURL = homeDirectory
            .appendingPathComponent("Library")
            .appendingPathComponent("DoNotDisturb")
            .appendingPathComponent("DB")
            .appendingPathComponent("Assertions.json")
    }

    @discardableResult
    func check() -> FullDiskAccessStatus {
        do {
            _ = try Data(contentsOf: assertionsURL)
            status = .allowed
            logger.info("permissions check passed; Assertions.json is readable")
        } catch {
            let nsError = error as NSError
            if isPermissionError(nsError) {
                status = .denied("FocusKeeper needs Full Disk Access to manage macOS Focus directly.")
                logger.error("permissions check failed; Full Disk Access required: \(error.localizedDescription)")
            } else {
                status = .unknown("FocusKeeper could not read the Focus assertions file: \(error.localizedDescription)")
                logger.error("permissions check failed; read error: \(error.localizedDescription)")
            }
        }

        return status
    }

    func openFullDiskAccessSettings() {
        let urls = [
            "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles",
            "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?Privacy_AllFiles"
        ]

        for rawURL in urls {
            guard let url = URL(string: rawURL), NSWorkspace.shared.open(url) else {
                continue
            }

            logger.info("opened Full Disk Access settings: \(rawURL)")
            return
        }

        logger.error("could not open Full Disk Access settings URL")
    }

    private func isPermissionError(_ error: NSError) -> Bool {
        if error.domain == NSCocoaErrorDomain {
            return error.code == NSFileReadNoPermissionError
        }

        return error.domain == NSPOSIXErrorDomain && error.code == Int(EACCES)
    }
}
