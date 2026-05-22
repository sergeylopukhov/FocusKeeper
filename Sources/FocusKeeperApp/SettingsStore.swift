import Foundation
import FocusBackend

struct FocusKeeperConfig: Codable, Equatable {
    var configVersion: Int
    var profiles: [FocusProfile]
    var selectedProfileID: String?
    var launchAtLoginEnabled: Bool
    var languagePreference: AppLanguagePreference
    var pauseState: PauseState

    init(
        configVersion: Int,
        profiles: [FocusProfile],
        selectedProfileID: String?,
        launchAtLoginEnabled: Bool,
        languagePreference: AppLanguagePreference,
        pauseState: PauseState
    ) {
        self.configVersion = configVersion
        self.profiles = profiles
        self.selectedProfileID = selectedProfileID
        self.launchAtLoginEnabled = launchAtLoginEnabled
        self.languagePreference = languagePreference
        self.pauseState = pauseState
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        configVersion = try container.decodeIfPresent(Int.self, forKey: .configVersion) ?? 2
        profiles = try container.decodeIfPresent([FocusProfile].self, forKey: .profiles) ?? []
        selectedProfileID = try container.decodeIfPresent(String.self, forKey: .selectedProfileID)
        launchAtLoginEnabled = try container.decodeIfPresent(Bool.self, forKey: .launchAtLoginEnabled) ?? false
        languagePreference = try container.decodeIfPresent(AppLanguagePreference.self, forKey: .languagePreference) ?? .system
        pauseState = try container.decodeIfPresent(PauseState.self, forKey: .pauseState) ?? .none
    }

    static func empty(languagePreference: AppLanguagePreference = .system) -> FocusKeeperConfig {
        let defaultProfile = FocusProfile.defaultProfile(languagePreference: languagePreference)
        return FocusKeeperConfig(
            configVersion: 2,
            profiles: [defaultProfile],
            selectedProfileID: defaultProfile.id,
            launchAtLoginEnabled: false,
            languagePreference: languagePreference,
            pauseState: .none
        )
    }
}

struct FocusProfile: Codable, Equatable, Identifiable {
    var id: String
    var name: String
    var isEnabled: Bool
    var selectedFocusModeIdentifier: String
    var watchedBundleIdentifiers: [String]
    var exitBehavior: FocusExitBehavior
    var offDelay: OffDelay
    var manualChangeBehavior: ManualChangeBehavior

    static func defaultProfile(languagePreference: AppLanguagePreference) -> FocusProfile {
        FocusProfile(
            id: UUID().uuidString,
            name: languagePreference.effectiveLanguage == .russian ? "Работа" : "Work",
            isEnabled: true,
            selectedFocusModeIdentifier: FocusMode.defaultWork.modeIdentifier,
            watchedBundleIdentifiers: [],
            exitBehavior: .turnOff,
            offDelay: .immediate,
            manualChangeBehavior: .respectManualChanges
        )
    }
}

enum FocusExitBehavior: String, Codable, CaseIterable, Identifiable {
    case turnOff
    case restorePrevious

    var id: String { rawValue }
}

enum ManualChangeBehavior: String, Codable, CaseIterable, Identifiable {
    case respectManualChanges
    case forceSelectedFocus

    var id: String { rawValue }
}

enum OffDelay: Codable, Equatable, Hashable, Identifiable {
    case immediate
    case seconds(Int)

    var id: String {
        switch self {
        case .immediate:
            return "immediate"
        case .seconds(let seconds):
            return "seconds-\(seconds)"
        }
    }

    var secondsValue: Int {
        switch self {
        case .immediate:
            return 0
        case .seconds(let seconds):
            return max(0, seconds)
        }
    }

    static let presetValues: [OffDelay] = [
        .immediate,
        .seconds(30),
        .seconds(60),
        .seconds(300),
        .seconds(900)
    ]

    enum CodingKeys: String, CodingKey {
        case type
        case seconds
    }

    init(from decoder: Decoder) throws {
        if let singleValue = try? decoder.singleValueContainer(),
           let legacySeconds = try? singleValue.decode(Int.self) {
            self = legacySeconds <= 0 ? .immediate : .seconds(legacySeconds)
            return
        }

        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decodeIfPresent(String.self, forKey: .type) ?? "immediate"
        if type == "seconds" {
            self = .seconds(max(0, try container.decodeIfPresent(Int.self, forKey: .seconds) ?? 0))
        } else {
            self = .immediate
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .immediate:
            try container.encode("immediate", forKey: .type)
        case .seconds(let seconds):
            try container.encode("seconds", forKey: .type)
            try container.encode(max(0, seconds), forKey: .seconds)
        }
    }
}

enum PauseState: Codable, Equatable {
    case none
    case until(Date)
    case indefinite

    var isPaused: Bool {
        switch self {
        case .none:
            return false
        case .indefinite:
            return true
        case .until(let date):
            return date > Date()
        }
    }

    var expirationDate: Date? {
        if case .until(let date) = self {
            return date
        }

        return nil
    }

    enum CodingKeys: String, CodingKey {
        case type
        case until
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decodeIfPresent(String.self, forKey: .type) ?? "none"
        switch type {
        case "indefinite":
            self = .indefinite
        case "until":
            if let date = try container.decodeIfPresent(Date.self, forKey: .until) {
                self = .until(date)
            } else {
                self = .none
            }
        default:
            self = .none
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .none:
            try container.encode("none", forKey: .type)
        case .indefinite:
            try container.encode("indefinite", forKey: .type)
        case .until(let date):
            try container.encode("until", forKey: .type)
            try container.encode(date, forKey: .until)
        }
    }
}

@MainActor
final class SettingsStore: ObservableObject {
    @Published private(set) var profiles: [FocusProfile]
    @Published private(set) var selectedProfileID: String?
    @Published private(set) var launchAtLoginEnabled: Bool
    @Published private(set) var languagePreference: AppLanguagePreference
    @Published private(set) var pauseState: PauseState

    private let configURL: URL
    private let fileManager: FileManager
    private var preservedRootObject: [String: Any]

    var effectiveLanguage: AppLanguage {
        languagePreference.effectiveLanguage
    }

    var selectedProfile: FocusProfile? {
        guard let selectedProfileID else {
            return profiles.first
        }

        return profiles.first { $0.id == selectedProfileID } ?? profiles.first
    }

    var selectedBundleIdentifiers: Set<String> {
        Set(selectedProfile?.watchedBundleIdentifiers ?? [])
    }

    var selectedFocusModeIdentifier: String {
        selectedProfile?.selectedFocusModeIdentifier ?? FocusMode.defaultWork.modeIdentifier
    }

    var focusExitBehavior: FocusExitBehavior {
        selectedProfile?.exitBehavior ?? .turnOff
    }

    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager

        let homeDirectory = fileManager.homeDirectoryForCurrentUser
        self.configURL = homeDirectory
            .appendingPathComponent("Library")
            .appendingPathComponent("Application Support")
            .appendingPathComponent("FocusKeeper")
            .appendingPathComponent("config.json")

        let loaded = Self.loadConfig(from: configURL)
        let loadedProfiles = loaded.config.profiles.isEmpty
            ? [FocusProfile.defaultProfile(languagePreference: loaded.config.languagePreference)]
            : loaded.config.profiles
        self.profiles = loadedProfiles
        self.selectedProfileID = loaded.config.selectedProfileID ?? loadedProfiles.first?.id
        self.launchAtLoginEnabled = loaded.config.launchAtLoginEnabled
        self.languagePreference = loaded.config.languagePreference
        self.pauseState = loaded.config.pauseState
        self.preservedRootObject = loaded.rawRoot

        if loaded.needsSave {
            save()
        }
    }

    func createProfile() {
        var profile = FocusProfile.defaultProfile(languagePreference: languagePreference)
        profile.name = uniqueProfileName(base: languagePreference.effectiveLanguage == .russian ? "Новый профиль" : "New Profile")
        profiles = profiles.map { existing in
            var existing = existing
            existing.isEnabled = false
            return existing
        }
        profiles.append(profile)
        selectedProfileID = profile.id
        save()
    }

    func deleteSelectedProfile() {
        guard profiles.count > 1, let selectedProfileID else {
            return
        }

        profiles.removeAll { $0.id == selectedProfileID }
        self.selectedProfileID = profiles.first?.id
        save()
    }

    func selectProfile(id: String) {
        guard profiles.contains(where: { $0.id == id }) else {
            return
        }

        selectedProfileID = id
        save()
    }

    func activateProfile(id: String) {
        guard profiles.contains(where: { $0.id == id }) else {
            return
        }

        selectedProfileID = id
        profiles = profiles.map { profile in
            var updatedProfile = profile
            updatedProfile.isEnabled = profile.id == id
            return updatedProfile
        }
        save()
        FocusKeeperLogger.shared.info("activated profile id=\(id)")
    }

    func moveSelectedProfileUp() {
        guard
            let selectedProfileID,
            let index = profiles.firstIndex(where: { $0.id == selectedProfileID }),
            index > 0
        else {
            return
        }

        profiles.swapAt(index, index - 1)
        save()
    }

    func moveSelectedProfileDown() {
        guard
            let selectedProfileID,
            let index = profiles.firstIndex(where: { $0.id == selectedProfileID }),
            index < profiles.count - 1
        else {
            return
        }

        profiles.swapAt(index, index + 1)
        save()
    }

    func updateSelectedProfile(_ update: (inout FocusProfile) -> Void) {
        guard
            let selectedProfileID,
            let index = profiles.firstIndex(where: { $0.id == selectedProfileID })
        else {
            return
        }

        let wasEnabled = profiles[index].isEnabled
        update(&profiles[index])
        profiles[index].watchedBundleIdentifiers = Array(Set(profiles[index].watchedBundleIdentifiers)).sorted()
        if !wasEnabled, profiles[index].isEnabled {
            let activeID = profiles[index].id
            profiles = profiles.map { profile in
                var updatedProfile = profile
                updatedProfile.isEnabled = profile.id == activeID
                return updatedProfile
            }
            self.selectedProfileID = activeID
        }
        save()
    }

    func isSelected(_ bundleIdentifier: String) -> Bool {
        selectedBundleIdentifiers.contains(bundleIdentifier)
    }

    func setSelected(_ isSelected: Bool, bundleIdentifier: String) {
        let normalizedBundleIdentifier = bundleIdentifier.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedBundleIdentifier.isEmpty else {
            return
        }

        updateSelectedProfile { profile in
            var identifiers = Set(profile.watchedBundleIdentifiers)
            if isSelected {
                identifiers.insert(normalizedBundleIdentifier)
            } else {
                identifiers.remove(normalizedBundleIdentifier)
            }
            profile.watchedBundleIdentifiers = identifiers.sorted()
        }
    }

    func addManualBundleIdentifier(_ bundleIdentifier: String) {
        setSelected(true, bundleIdentifier: bundleIdentifier)
    }

    func removeBundleIdentifier(_ bundleIdentifier: String) {
        setSelected(false, bundleIdentifier: bundleIdentifier)
    }

    func setSelectedFocusModeIdentifier(_ modeIdentifier: String) {
        let normalizedModeIdentifier = modeIdentifier.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedModeIdentifier.isEmpty else {
            return
        }

        updateSelectedProfile { profile in
            profile.selectedFocusModeIdentifier = normalizedModeIdentifier
        }
        FocusKeeperLogger.shared.info("selected Focus mode changed; modeIdentifier=\(normalizedModeIdentifier)")
    }

    func setLaunchAtLoginEnabled(_ isEnabled: Bool) {
        launchAtLoginEnabled = isEnabled
        save()
    }

    func setLanguagePreference(_ preference: AppLanguagePreference) {
        languagePreference = preference
        save()
    }

    func setFocusExitBehavior(_ behavior: FocusExitBehavior) {
        updateSelectedProfile { profile in
            profile.exitBehavior = behavior
        }
        FocusKeeperLogger.shared.info("Focus exit behavior changed; behavior=\(behavior.rawValue)")
    }

    func setPauseState(_ pauseState: PauseState) {
        self.pauseState = normalizedPauseState(pauseState)
        save()
        FocusKeeperLogger.shared.info("pause state changed; paused=\(self.pauseState.isPaused)")
    }

    func resumeAutomation() {
        setPauseState(.none)
    }

    func normalizeExpiredPauseIfNeeded() {
        if case .until(let date) = pauseState, date <= Date() {
            pauseState = .none
            save()
        }
    }

    func resolveSelectedFocusMode(from modes: [FocusMode]) throws -> FocusMode {
        guard let selectedProfile else {
            throw FocusModeDiscoveryError.noAvailableModes
        }

        return try resolveFocusMode(for: selectedProfile, from: modes)
    }

    func resolveFocusMode(for profile: FocusProfile, from modes: [FocusMode]) throws -> FocusMode {
        if let selectedMode = modes.first(where: { $0.modeIdentifier == profile.selectedFocusModeIdentifier }) {
            return selectedMode
        }

        if let defaultWorkMode = modes.first(where: { $0.modeIdentifier == FocusMode.defaultWork.modeIdentifier }) {
            if profile.id == selectedProfileID {
                setSelectedFocusModeIdentifier(defaultWorkMode.modeIdentifier)
            }
            return defaultWorkMode
        }

        if modes.isEmpty {
            throw FocusModeDiscoveryError.noAvailableModes
        }

        throw FocusModeDiscoveryError.selectedModeUnavailable(profile.selectedFocusModeIdentifier)
    }

    private func uniqueProfileName(base: String) -> String {
        let existingNames = Set(profiles.map(\.name))
        guard existingNames.contains(base) else {
            return base
        }

        var index = 2
        while existingNames.contains("\(base) \(index)") {
            index += 1
        }

        return "\(base) \(index)"
    }

    private func normalizedPauseState(_ pauseState: PauseState) -> PauseState {
        if case .until(let date) = pauseState, date <= Date() {
            return .none
        }

        return pauseState
    }

    private func save() {
        let config = FocusKeeperConfig(
            configVersion: 2,
            profiles: profiles,
            selectedProfileID: selectedProfileID,
            launchAtLoginEnabled: launchAtLoginEnabled,
            languagePreference: languagePreference,
            pauseState: normalizedPauseState(pauseState)
        )

        do {
            try fileManager.createDirectory(
                at: configURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )

            let encoded = try JSONEncoder.prettyPrinted.encode(config)
            guard var configObject = try JSONSerialization.jsonObject(with: encoded) as? [String: Any] else {
                throw CocoaError(.coderInvalidValue)
            }

            for (key, value) in preservedRootObject where configObject[key] == nil {
                configObject[key] = value
            }

            let data = try JSONSerialization.data(withJSONObject: configObject, options: [.prettyPrinted, .sortedKeys])
            try data.write(to: configURL, options: [.atomic])
            preservedRootObject = configObject
        } catch {
            NSLog("FocusKeeper settings save failed: \(error.localizedDescription)")
        }
    }

    private static func loadConfig(from url: URL) -> (config: FocusKeeperConfig, rawRoot: [String: Any], needsSave: Bool) {
        do {
            let data = try Data(contentsOf: url)
            let rawRoot = (try? JSONSerialization.jsonObject(with: data) as? [String: Any]) ?? [:]

            if rawRoot["profiles"] != nil {
                let config = try JSONDecoder.focusKeeper.decode(FocusKeeperConfig.self, from: data)
                return (config, rawRoot, false)
            }

            let migrated = try migrateLegacyConfig(from: data, rawRoot: rawRoot)
            return (migrated, rawRoot, true)
        } catch CocoaError.fileReadNoSuchFile {
            return (.empty(), [:], true)
        } catch {
            NSLog("FocusKeeper settings load failed: \(error.localizedDescription)")
            return (.empty(), [:], true)
        }
    }

    private static func migrateLegacyConfig(from data: Data, rawRoot: [String: Any]) throws -> FocusKeeperConfig {
        struct LegacyConfig: Decodable {
            var selectedBundleIdentifiers: [String]?
            var selectedFocusModeIdentifier: String?
            var launchAtLoginEnabled: Bool?
            var languagePreference: AppLanguagePreference?
            var focusExitBehavior: FocusExitBehavior?
        }

        let legacy = try JSONDecoder.focusKeeper.decode(LegacyConfig.self, from: data)
        let languagePreference = legacy.languagePreference ?? .system
        var profile = FocusProfile.defaultProfile(languagePreference: languagePreference)
        profile.selectedFocusModeIdentifier = legacy.selectedFocusModeIdentifier ?? FocusMode.defaultWork.modeIdentifier
        profile.watchedBundleIdentifiers = Array(Set(legacy.selectedBundleIdentifiers ?? [])).sorted()
        profile.exitBehavior = legacy.focusExitBehavior ?? .turnOff

        return FocusKeeperConfig(
            configVersion: 2,
            profiles: [profile],
            selectedProfileID: profile.id,
            launchAtLoginEnabled: legacy.launchAtLoginEnabled ?? false,
            languagePreference: languagePreference,
            pauseState: .none
        )
    }
}

private extension JSONEncoder {
    static var prettyPrinted: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }
}

private extension JSONDecoder {
    static var focusKeeper: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
