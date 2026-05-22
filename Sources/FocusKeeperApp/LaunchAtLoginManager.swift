import Foundation
import FocusBackend

enum LaunchAtLoginError: Error, LocalizedError {
    case missingExecutableURL
    case unsupportedExecutableLocation(String)
    case plistWriteFailed(String)
    case plistRemoveFailed(String)

    var errorDescription: String? {
        switch self {
        case .missingExecutableURL:
            return "FocusKeeper could not determine its executable path."
        case .unsupportedExecutableLocation(let path):
            return "Launch at Login fallback cannot register this executable path: \(path)"
        case .plistWriteFailed(let message):
            return "Could not enable Launch at Login: \(message)"
        case .plistRemoveFailed(let message):
            return "Could not disable Launch at Login: \(message)"
        }
    }
}

@MainActor
final class LaunchAtLoginManager: ObservableObject {
    @Published private(set) var lastErrorMessage: String?

    let implementationDescription = "Launch at Login uses a user LaunchAgent fallback because this SwiftPM executable is not currently packaged as a signed app bundle for SMAppService."

    private let fileManager: FileManager
    private let logger = FocusKeeperLogger.shared
    private let launchAgentURL: URL

    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
        let homeDirectory = fileManager.homeDirectoryForCurrentUser
        self.launchAgentURL = homeDirectory
            .appendingPathComponent("Library")
            .appendingPathComponent("LaunchAgents")
            .appendingPathComponent("com.focuskeeper.app.plist")
    }

    func refresh(settingsStore: SettingsStore) {
        let isRegistered = fileManager.fileExists(atPath: launchAgentURL.path)
        if settingsStore.launchAtLoginEnabled != isRegistered {
            settingsStore.setLaunchAtLoginEnabled(isRegistered)
        }
    }

    func setEnabled(_ isEnabled: Bool, settingsStore: SettingsStore) {
        do {
            if isEnabled {
                try enable()
            } else {
                try disable()
            }

            lastErrorMessage = nil
            settingsStore.setLaunchAtLoginEnabled(isEnabled)
        } catch {
            let message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            lastErrorMessage = message
            logger.log(error, context: "LaunchAtLogin")
            settingsStore.setLaunchAtLoginEnabled(false)
        }
    }

    private func enable() throws {
        guard let executableURL = Bundle.main.executableURL else {
            throw LaunchAtLoginError.missingExecutableURL
        }

        let executablePath = executableURL.path
        guard executablePath.hasPrefix("/") else {
            throw LaunchAtLoginError.unsupportedExecutableLocation(executablePath)
        }

        let plist: [String: Any] = [
            "Label": "com.focuskeeper.app",
            "ProgramArguments": [executablePath],
            "RunAtLoad": true,
            "KeepAlive": false,
            "StandardOutPath": FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent("Library")
                .appendingPathComponent("Logs")
                .appendingPathComponent("FocusKeeper.launchd.out.log")
                .path,
            "StandardErrorPath": FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent("Library")
                .appendingPathComponent("Logs")
                .appendingPathComponent("FocusKeeper.launchd.err.log")
                .path
        ]

        do {
            let data = try PropertyListSerialization.data(
                fromPropertyList: plist,
                format: .xml,
                options: 0
            )
            try fileManager.createDirectory(
                at: launchAgentURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try data.write(to: launchAgentURL, options: [.atomic])
            logger.info("Launch at Login enabled with LaunchAgent fallback at \(launchAgentURL.path)")
        } catch {
            throw LaunchAtLoginError.plistWriteFailed(error.localizedDescription)
        }
    }

    private func disable() throws {
        guard fileManager.fileExists(atPath: launchAgentURL.path) else {
            logger.info("Launch at Login already disabled; LaunchAgent not present")
            return
        }

        do {
            try fileManager.removeItem(at: launchAgentURL)
            logger.info("Launch at Login disabled; removed LaunchAgent fallback")
        } catch {
            throw LaunchAtLoginError.plistRemoveFailed(error.localizedDescription)
        }
    }
}
