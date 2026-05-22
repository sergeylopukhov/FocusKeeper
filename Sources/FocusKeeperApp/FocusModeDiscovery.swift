import Foundation
import FocusBackend

struct FocusMode: Identifiable, Equatable {
    var id: String { modeIdentifier }

    let name: String
    let modeIdentifier: String
    let symbolImageName: String?

    static let defaultWork = FocusMode(
        name: "Работа",
        modeIdentifier: "com.apple.focus.work",
        symbolImageName: nil
    )
}

enum FocusModeDiscoveryError: Error, LocalizedError, Equatable {
    case noAvailableModes
    case selectedModeUnavailable(String)

    var errorDescription: String? {
        switch self {
        case .noAvailableModes:
            return "No valid Focus modes are available in ModeConfigurations.json."
        case .selectedModeUnavailable(let modeIdentifier):
            return "Selected Focus mode no longer exists: \(modeIdentifier)"
        }
    }
}

@MainActor
final class FocusModeDiscovery: ObservableObject {
    @Published private(set) var modes: [FocusMode] = []
    @Published private(set) var errorMessage: String?

    private let modeConfigurationsURL: URL
    private let settingsStore: SettingsStore
    private let logger = FocusKeeperLogger.shared

    init(settingsStore: SettingsStore, fileManager: FileManager = .default) {
        self.settingsStore = settingsStore

        let homeDirectory = fileManager.homeDirectoryForCurrentUser
        self.modeConfigurationsURL = homeDirectory
            .appendingPathComponent("Library")
            .appendingPathComponent("DoNotDisturb")
            .appendingPathComponent("DB")
            .appendingPathComponent("ModeConfigurations.json")
    }

    @discardableResult
    func refresh() -> [FocusMode] {
        do {
            let discoveredModes = try loadModes()
            modes = discoveredModes
            errorMessage = nil
            _ = try settingsStore.resolveSelectedFocusMode(from: discoveredModes)
            logger.info("Focus mode discovery succeeded; modes=\(discoveredModes.count)")
            return discoveredModes
        } catch {
            let message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            modes = [FocusMode.defaultWork]
            errorMessage = "\(message) Using verified default: \(FocusMode.defaultWork.name) (\(FocusMode.defaultWork.modeIdentifier))."
            settingsStore.setSelectedFocusModeIdentifier(FocusMode.defaultWork.modeIdentifier)
            logger.log(error, context: "FocusModeDiscovery")
            logger.info("Focus mode discovery fell back to verified default modeIdentifier=\(FocusMode.defaultWork.modeIdentifier)")
            return modes
        }
    }

    func selectedMode() throws -> FocusMode {
        if modes.isEmpty {
            _ = refresh()
        }

        if modes.count == 1, modes[0].modeIdentifier == FocusMode.defaultWork.modeIdentifier {
            return modes[0]
        }

        return try settingsStore.resolveSelectedFocusMode(from: modes)
    }

    private func loadModes() throws -> [FocusMode] {
        let data: Data
        do {
            data = try Data(contentsOf: modeConfigurationsURL)
        } catch {
            throw mapReadError(error)
        }

        let root: [String: Any]
        do {
            guard let parsedRoot = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                throw FocusBackendError.invalidStructure("ModeConfigurations top-level JSON value is not an object")
            }

            root = parsedRoot
        } catch let backendError as FocusBackendError {
            throw backendError
        } catch {
            throw FocusBackendError.invalidJSON(modeConfigurationsURL)
        }

        let modeConfigurationObjects = findModeConfigurationObjects(in: root)
        let modes = modeConfigurationObjects
            .compactMap(parseMode)
            .filter { !excludedModeIdentifiers.contains($0.modeIdentifier) }

        guard !modes.isEmpty else {
            throw FocusModeDiscoveryError.noAvailableModes
        }

        return uniqueModes(modes).sorted {
            $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }
    }

    private func findModeConfigurationObjects(in object: Any) -> [[String: Any]] {
        var results: [[String: Any]] = []

        if let dictionary = object as? [String: Any] {
            if parseMode(from: dictionary) != nil {
                results.append(dictionary)
            }

            for (key, value) in dictionary {
                if key == "modeConfigurations" {
                    if let array = value as? [Any] {
                        results.append(contentsOf: array.compactMap { $0 as? [String: Any] })
                    } else if let nestedDictionary = value as? [String: Any] {
                        results.append(contentsOf: nestedDictionary.values.compactMap { $0 as? [String: Any] })
                    }
                }

                results.append(contentsOf: findModeConfigurationObjects(in: value))
            }
        } else if let array = object as? [Any] {
            for value in array {
                results.append(contentsOf: findModeConfigurationObjects(in: value))
            }
        }

        return results
    }

    private func parseMode(from object: [String: Any]) -> FocusMode? {
        guard let modeIdentifier = firstAppleModeIdentifier(in: object) ?? firstString(
            in: object,
            matchingKeys: [
                "modeIdentifier",
                "modeConfigurationIdentifier",
                "identifier",
                "semanticIdentifier",
                "assertionDetailsModeIdentifier"
            ]
        ), isUsableModeIdentifier(modeIdentifier) else {
            return nil
        }

        let name = firstString(
            in: object,
            matchingKeys: [
                "name",
                "displayName",
                "localizedName",
                "modeName",
                "modeConfigurationName",
                "title"
            ]
        ) ?? fallbackName(for: modeIdentifier)

        let symbolImageName = firstString(
            in: object,
            matchingKeys: ["symbolImageName", "symbolName", "imageName"]
        )

        return FocusMode(
            name: name,
            modeIdentifier: modeIdentifier,
            symbolImageName: symbolImageName
        )
    }

    private func firstString(in object: Any, matchingKeys keys: [String]) -> String? {
        if let dictionary = object as? [String: Any] {
            for (key, value) in dictionary {
                if keys.contains(key), let string = normalizedString(value) {
                    return string
                }
            }

            for value in dictionary.values {
                if let string = firstString(in: value, matchingKeys: keys) {
                    return string
                }
            }
        } else if let array = object as? [Any] {
            for value in array {
                if let string = firstString(in: value, matchingKeys: keys) {
                    return string
                }
            }
        }

        return nil
    }

    private func normalizedString(_ value: Any) -> String? {
        guard let string = value as? String else {
            return nil
        }

        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private func firstAppleModeIdentifier(in object: Any) -> String? {
        if let dictionary = object as? [String: Any] {
            for value in dictionary.values {
                if let string = normalizedString(value),
                   isUsableModeIdentifier(string) {
                    return string
                }

                if let nested = firstAppleModeIdentifier(in: value) {
                    return nested
                }
            }
        } else if let array = object as? [Any] {
            for value in array {
                if let nested = firstAppleModeIdentifier(in: value) {
                    return nested
                }
            }
        }

        return nil
    }

    private func isUsableModeIdentifier(_ value: String) -> Bool {
        value.hasPrefix("com.apple.focus.")
            || value.hasPrefix("com.apple.donotdisturb.")
            || value.hasPrefix("com.apple.sleep.")
    }

    private var excludedModeIdentifiers: Set<String> {
        [
            "com.apple.focus.reduce-interruptions"
        ]
    }

    private func fallbackName(for modeIdentifier: String) -> String {
        if modeIdentifier == FocusMode.defaultWork.modeIdentifier {
            return FocusMode.defaultWork.name
        }

        return modeIdentifier
    }

    private func uniqueModes(_ modes: [FocusMode]) -> [FocusMode] {
        var seen: Set<String> = []
        var result: [FocusMode] = []

        for mode in modes where !seen.contains(mode.modeIdentifier) {
            seen.insert(mode.modeIdentifier)
            result.append(mode)
        }

        return result
    }

    private func mapReadError(_ error: Error) -> Error {
        let nsError = error as NSError
        if nsError.domain == NSCocoaErrorDomain {
            switch nsError.code {
            case NSFileReadNoPermissionError:
                return FocusBackendError.permissionDenied(modeConfigurationsURL)
            case NSFileReadNoSuchFileError:
                return FocusBackendError.missingAssertionsFile(modeConfigurationsURL)
            default:
                break
            }
        }

        if nsError.domain == NSPOSIXErrorDomain && nsError.code == Int(EACCES) {
            return FocusBackendError.permissionDenied(modeConfigurationsURL)
        }

        return error
    }
}
