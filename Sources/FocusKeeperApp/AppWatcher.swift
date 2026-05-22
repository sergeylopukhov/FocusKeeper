import AppKit
import Combine
import FocusBackend

enum FocusKeeperAutomationState: Equatable {
    case paused
    case error
    case pendingOff(profileID: String, dueDate: Date)
    case active(profileID: String)
    case idle
}

struct AppWatcherSnapshot: Equatable {
    var state: FocusKeeperAutomationState
    var watchedAppsRunningCount: Int
    var runningWatchedBundleIdentifiers: [String]
    var desiredFocusEnabled: Bool
    var actualFocusStatus: FocusStatus
    var activeProfileID: String?
    var activeProfileName: String?
    var selectedFocusModeIdentifier: String?
    var pendingOffProfileID: String?
    var pendingOffDueDate: Date?
    var pauseState: PauseState
    var lastBackendAction: String?
    var lastBackendActionDate: Date?
    var lastSleepWakeSyncDate: Date?
    var errorMessage: String?
}

@MainActor
final class AppWatcher {
    private let settingsStore: SettingsStore
    private let focusBackend: FocusBackend
    private let focusModeDiscovery: FocusModeDiscovery
    private let workspace: NSWorkspace
    private let notificationCenter: NotificationCenter
    private let onSnapshotChange: (AppWatcherSnapshot) -> Void
    private let logger = FocusKeeperLogger.shared

    private var settingsCancellables: Set<AnyCancellable> = []
    private var reconciliationTimer: Timer?
    private var pendingOffTimer: Timer?
    private var pauseExpirationTimer: Timer?
    private var pendingSyncWorkItem: DispatchWorkItem?
    private var wakeSyncWorkItem: DispatchWorkItem?
    private var activeProfileID: String?
    private var activationSnapshot: FocusAssertionSnapshot?
    private var focusKeeperOwnsCurrentFocus = false
    private var lastAppliedModeIdentifier: String?
    private var pendingOffContext: PendingOffContext?
    private var lastBackendAction: String?
    private var lastBackendActionDate: Date?
    private var lastSleepWakeSyncDate: Date?

    private struct PendingOffContext {
        var profile: FocusProfile
        var snapshot: FocusAssertionSnapshot?
        var focusKeeperOwnsFocus: Bool
        var dueDate: Date
    }

    private(set) var snapshot = AppWatcherSnapshot(
        state: .idle,
        watchedAppsRunningCount: 0,
        runningWatchedBundleIdentifiers: [],
        desiredFocusEnabled: false,
        actualFocusStatus: .unknown,
        activeProfileID: nil,
        activeProfileName: nil,
        selectedFocusModeIdentifier: nil,
        pendingOffProfileID: nil,
        pendingOffDueDate: nil,
        pauseState: .none,
        lastBackendAction: nil,
        lastBackendActionDate: nil,
        lastSleepWakeSyncDate: nil,
        errorMessage: nil
    ) {
        didSet {
            guard oldValue != snapshot else {
                return
            }

            onSnapshotChange(snapshot)
        }
    }

    init(
        settingsStore: SettingsStore,
        focusBackend: FocusBackend,
        focusModeDiscovery: FocusModeDiscovery,
        workspace: NSWorkspace = .shared,
        notificationCenter: NotificationCenter = NSWorkspace.shared.notificationCenter,
        onSnapshotChange: @escaping (AppWatcherSnapshot) -> Void
    ) {
        self.settingsStore = settingsStore
        self.focusBackend = focusBackend
        self.focusModeDiscovery = focusModeDiscovery
        self.workspace = workspace
        self.notificationCenter = notificationCenter
        self.onSnapshotChange = onSnapshotChange
    }

    func start() {
        notificationCenter.addObserver(
            self,
            selector: #selector(runningApplicationsDidChange),
            name: NSWorkspace.didLaunchApplicationNotification,
            object: nil
        )
        notificationCenter.addObserver(
            self,
            selector: #selector(runningApplicationsDidChange),
            name: NSWorkspace.didTerminateApplicationNotification,
            object: nil
        )
        notificationCenter.addObserver(
            self,
            selector: #selector(workspaceWillSleep),
            name: NSWorkspace.willSleepNotification,
            object: nil
        )
        notificationCenter.addObserver(
            self,
            selector: #selector(workspaceDidWake),
            name: NSWorkspace.didWakeNotification,
            object: nil
        )
        notificationCenter.addObserver(
            self,
            selector: #selector(sessionDidBecomeActive),
            name: NSWorkspace.sessionDidBecomeActiveNotification,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(syncNowRequested),
            name: .focusKeeperSyncNowRequested,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(cancelPendingOffRequested),
            name: .focusKeeperCancelPendingOffRequested,
            object: nil
        )

        settingsStore.$profiles
            .sink { [weak self] _ in
                Task { @MainActor in
                    self?.scheduleDebouncedSync(reason: "profiles changed")
                }
            }
            .store(in: &settingsCancellables)

        settingsStore.$selectedProfileID
            .sink { [weak self] _ in
                Task { @MainActor in
                    self?.scheduleDebouncedSync(reason: "selected profile changed")
                }
            }
            .store(in: &settingsCancellables)

        settingsStore.$pauseState
            .sink { [weak self] _ in
                Task { @MainActor in
                    self?.schedulePauseExpirationTimer()
                    self?.scheduleDebouncedSync(reason: "pause changed")
                }
            }
            .store(in: &settingsCancellables)

        reconciliationTimer = Timer.scheduledTimer(withTimeInterval: 10, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.syncNow(reason: "periodic reconciliation", force: false)
            }
        }

        schedulePauseExpirationTimer()
        syncNow(reason: "app start", force: true)
    }

    func stop() {
        notificationCenter.removeObserver(self)
        NotificationCenter.default.removeObserver(self)
        settingsCancellables.removeAll()
        pendingSyncWorkItem?.cancel()
        wakeSyncWorkItem?.cancel()
        pendingSyncWorkItem = nil
        wakeSyncWorkItem = nil
        reconciliationTimer?.invalidate()
        pendingOffTimer?.invalidate()
        pauseExpirationTimer?.invalidate()
        reconciliationTimer = nil
        pendingOffTimer = nil
        pauseExpirationTimer = nil
    }

    func syncNow(reason: String = "manual sync", force: Bool = false) {
        settingsStore.normalizeExpiredPauseIfNeeded()

        if settingsStore.pauseState.isPaused {
            logger.info("sync skipped because FocusKeeper is paused; reason=\(reason)")
            refreshSnapshot(
                state: .paused,
                activeProfile: nil,
                runningBundleIDs: runningWatchedBundleIdentifiers(),
                actualStatus: currentActualStatusForSnapshot(),
                errorMessage: nil
            )
            return
        }

        let runningBundleIDs = runningWatchedBundleIdentifiers()
        let matchingProfile = highestPriorityMatchingProfile(runningBundleIDs: Set(runningBundleIDs))

        logger.info(
            "sync requested; reason=\(reason); matchingProfile=\(matchingProfile?.name ?? "none"); runningWatched=\(runningBundleIDs.count); force=\(force)"
        )

        if force {
            pendingSyncWorkItem?.cancel()
            pendingSyncWorkItem = nil
            reconcile(matchingProfile: matchingProfile, runningBundleIDs: runningBundleIDs, reason: reason, force: true)
            return
        }

        scheduleApply(matchingProfile: matchingProfile, runningBundleIDs: runningBundleIDs, reason: reason)
    }

    func cancelPendingOff() {
        guard pendingOffContext != nil else {
            return
        }

        logger.info("pending off canceled by user")
        pendingOffContext = nil
        pendingOffTimer?.invalidate()
        pendingOffTimer = nil
        refreshSnapshot(
            state: activeProfileID.map { .active(profileID: $0) } ?? .idle,
            activeProfile: profile(id: activeProfileID),
            runningBundleIDs: runningWatchedBundleIdentifiers(),
            actualStatus: currentActualStatusForSnapshot(),
            errorMessage: nil
        )
    }

    @objc private func runningApplicationsDidChange(_ notification: Notification) {
        let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
        let bundleIdentifier = app?.bundleIdentifier ?? "unknown"
        let appName = app?.localizedName ?? bundleIdentifier
        logger.info("workspace event \(notification.name.rawValue); app=\(appName); bundleID=\(bundleIdentifier)")
        scheduleDebouncedSync(reason: notification.name.rawValue)
    }

    @objc private func syncNowRequested(_ notification: Notification) {
        syncNow(reason: "menu sync now", force: true)
    }

    @objc private func cancelPendingOffRequested(_ notification: Notification) {
        cancelPendingOff()
    }

    @objc private func workspaceWillSleep(_ notification: Notification) {
        logger.info("workspace will sleep")
    }

    @objc private func workspaceDidWake(_ notification: Notification) {
        scheduleWakeSync(reason: "workspace did wake")
    }

    @objc private func sessionDidBecomeActive(_ notification: Notification) {
        scheduleWakeSync(reason: "session became active")
    }

    private func scheduleWakeSync(reason: String) {
        logger.info("wake/session event; scheduling reconciliation; reason=\(reason)")
        wakeSyncWorkItem?.cancel()
        let workItem = DispatchWorkItem { [weak self] in
            Task { @MainActor in
                guard let self else { return }
                self.lastSleepWakeSyncDate = Date()
                self.syncNow(reason: reason, force: true)
            }
        }
        wakeSyncWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0, execute: workItem)
    }

    private func scheduleDebouncedSync(reason: String) {
        pendingSyncWorkItem?.cancel()
        let workItem = DispatchWorkItem { [weak self] in
            Task { @MainActor in
                self?.syncNow(reason: "debounced \(reason)", force: false)
            }
        }
        pendingSyncWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5, execute: workItem)
        logger.info("debounced sync scheduled; reason=\(reason); delay=1.5s")
    }

    private func scheduleApply(matchingProfile: FocusProfile?, runningBundleIDs: [String], reason: String) {
        pendingSyncWorkItem?.cancel()
        let workItem = DispatchWorkItem { [weak self] in
            Task { @MainActor in
                self?.reconcile(
                    matchingProfile: matchingProfile,
                    runningBundleIDs: runningBundleIDs,
                    reason: "debounced apply \(reason)",
                    force: false
                )
            }
        }
        pendingSyncWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5, execute: workItem)
        logger.info("state apply scheduled; profile=\(matchingProfile?.name ?? "none"); reason=\(reason); delay=1.5s")
    }

    private func reconcile(matchingProfile: FocusProfile?, runningBundleIDs: [String], reason: String, force: Bool) {
        if let pendingOffContext {
            if let matchingProfile, matchingProfile.id == pendingOffContext.profile.id {
                cancelPendingOff()
            } else if let matchingProfile, matchingProfile.id != pendingOffContext.profile.id {
                cancelPendingOff()
            } else if pendingOffContext.dueDate <= Date() {
                applyPendingOff(reason: "pending off elapsed during \(reason)")
                return
            } else {
                refreshSnapshot(
                    state: .pendingOff(profileID: pendingOffContext.profile.id, dueDate: pendingOffContext.dueDate),
                    activeProfile: nil,
                    runningBundleIDs: runningBundleIDs,
                    actualStatus: currentActualStatusForSnapshot(profile: pendingOffContext.profile),
                    errorMessage: nil
                )
                schedulePendingOffTimer()
                return
            }
        }

        guard let matchingProfile else {
            handleNoActiveProfile(runningBundleIDs: runningBundleIDs, reason: reason)
            return
        }

        do {
            try activate(profile: matchingProfile, runningBundleIDs: runningBundleIDs, reason: reason, force: force)
        } catch {
            handleError(error, activeProfile: matchingProfile, runningBundleIDs: runningBundleIDs)
        }
    }

    private func activate(profile: FocusProfile, runningBundleIDs: [String], reason: String, force: Bool) throws {
        let actualStatus = readActualStatus(modeIdentifier: profile.selectedFocusModeIdentifier)
        let profileChanged = activeProfileID != profile.id

        logger.info(
            "activate profile requested; profile=\(profile.name); modeIdentifier=\(profile.selectedFocusModeIdentifier); actual=\(actualStatus.status.rawValue); profileChanged=\(profileChanged); manualBehavior=\(profile.manualChangeBehavior.rawValue); force=\(force); reason=\(reason)"
        )

        if profileChanged {
            activeProfileID = profile.id
            activationSnapshot = profile.exitBehavior == .restorePrevious
                ? try focusBackend.captureAssertionSnapshot()
                : nil
            focusKeeperOwnsCurrentFocus = true
            lastAppliedModeIdentifier = nil
        }

        switch profile.manualChangeBehavior {
        case .respectManualChanges:
            if !profileChanged,
               focusKeeperOwnsCurrentFocus,
               lastAppliedModeIdentifier == profile.selectedFocusModeIdentifier,
               actualStatus.status != .enabled {
                focusKeeperOwnsCurrentFocus = false
                logger.info("manual Focus change detected; respecting user change for profile=\(profile.name)")
            }

            if profileChanged || lastAppliedModeIdentifier != profile.selectedFocusModeIdentifier {
                if actualStatus.status != .enabled {
                    try focusBackend.enableFocus(modeIdentifier: profile.selectedFocusModeIdentifier)
                    recordBackendAction("enable \(profile.selectedFocusModeIdentifier)")
                }
                focusKeeperOwnsCurrentFocus = true
                lastAppliedModeIdentifier = profile.selectedFocusModeIdentifier
            }

        case .forceSelectedFocus:
            if actualStatus.status != .enabled {
                try focusBackend.enableFocus(modeIdentifier: profile.selectedFocusModeIdentifier)
                recordBackendAction("enable \(profile.selectedFocusModeIdentifier)")
                focusKeeperOwnsCurrentFocus = true
                lastAppliedModeIdentifier = profile.selectedFocusModeIdentifier
            }
        }

        let updatedStatus = readActualStatus(modeIdentifier: profile.selectedFocusModeIdentifier)
        refreshSnapshot(
            state: .active(profileID: profile.id),
            activeProfile: profile,
            runningBundleIDs: runningBundleIDs,
            actualStatus: updatedStatus,
            errorMessage: updatedStatus.errorMessage
        )
    }

    private func handleNoActiveProfile(runningBundleIDs: [String], reason: String) {
        guard let existingActiveProfile = profile(id: activeProfileID) else {
            refreshSnapshot(
                state: .idle,
                activeProfile: nil,
                runningBundleIDs: runningBundleIDs,
                actualStatus: currentActualStatusForSnapshot(),
                errorMessage: nil
            )
            return
        }

        let delay = existingActiveProfile.offDelay.secondsValue
        if delay > 0 {
            let dueDate = Date().addingTimeInterval(TimeInterval(delay))
            pendingOffContext = PendingOffContext(
                profile: existingActiveProfile,
                snapshot: activationSnapshot,
                focusKeeperOwnsFocus: focusKeeperOwnsCurrentFocus,
                dueDate: dueDate
            )
            pendingOffTimer?.invalidate()
            schedulePendingOffTimer()
            activeProfileID = nil
            logger.info("pending off started; profile=\(existingActiveProfile.name); seconds=\(delay); reason=\(reason)")
            refreshSnapshot(
                state: .pendingOff(profileID: existingActiveProfile.id, dueDate: dueDate),
                activeProfile: nil,
                runningBundleIDs: runningBundleIDs,
                actualStatus: currentActualStatusForSnapshot(profile: existingActiveProfile),
                errorMessage: nil
            )
        } else {
            applyExit(for: existingActiveProfile, reason: reason)
            refreshSnapshot(
                state: .idle,
                activeProfile: nil,
                runningBundleIDs: runningBundleIDs,
                actualStatus: currentActualStatusForSnapshot(profile: existingActiveProfile),
                errorMessage: nil
            )
        }
    }

    private func schedulePendingOffTimer() {
        pendingOffTimer?.invalidate()
        guard let pendingOffContext else {
            return
        }

        let interval = max(0, pendingOffContext.dueDate.timeIntervalSinceNow)
        pendingOffTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: false) { [weak self] _ in
            Task { @MainActor in
                self?.applyPendingOff(reason: "pending off timer elapsed")
            }
        }
    }

    private func applyPendingOff(reason: String) {
        guard let context = pendingOffContext else {
            return
        }

        let runningBundleIDs = runningWatchedBundleIdentifiers()
        if let matchingProfile = highestPriorityMatchingProfile(runningBundleIDs: Set(runningBundleIDs)) {
            pendingOffContext = nil
            pendingOffTimer?.invalidate()
            pendingOffTimer = nil
            reconcile(matchingProfile: matchingProfile, runningBundleIDs: runningBundleIDs, reason: "\(reason); profile became active", force: true)
            return
        }

        activationSnapshot = context.snapshot
        focusKeeperOwnsCurrentFocus = context.focusKeeperOwnsFocus
        applyExit(for: context.profile, reason: reason)
        pendingOffContext = nil
        pendingOffTimer?.invalidate()
        pendingOffTimer = nil
        refreshSnapshot(
            state: .idle,
            activeProfile: nil,
            runningBundleIDs: runningBundleIDs,
            actualStatus: currentActualStatusForSnapshot(profile: context.profile),
            errorMessage: nil
        )
    }

    private func applyExit(for profile: FocusProfile, reason: String) {
        defer {
            activeProfileID = nil
            activationSnapshot = nil
            focusKeeperOwnsCurrentFocus = false
            lastAppliedModeIdentifier = nil
        }

        guard focusKeeperOwnsCurrentFocus else {
            logger.info("exit skipped because FocusKeeper no longer owns Focus; profile=\(profile.name); reason=\(reason)")
            return
        }

        do {
            switch profile.exitBehavior {
            case .turnOff:
                try focusBackend.disableWorkFocus()
                recordBackendAction("disable")
            case .restorePrevious:
                if let activationSnapshot {
                    try focusBackend.restoreAssertionSnapshot(activationSnapshot)
                    recordBackendAction("restore previous")
                } else {
                    try focusBackend.disableWorkFocus()
                    recordBackendAction("disable fallback")
                }
            }
            logger.info("exit applied; profile=\(profile.name); reason=\(reason)")
        } catch {
            handleError(error, activeProfile: profile, runningBundleIDs: runningWatchedBundleIdentifiers())
        }
    }

    private func schedulePauseExpirationTimer() {
        pauseExpirationTimer?.invalidate()
        pauseExpirationTimer = nil
        settingsStore.normalizeExpiredPauseIfNeeded()

        guard let expirationDate = settingsStore.pauseState.expirationDate else {
            return
        }

        pauseExpirationTimer = Timer.scheduledTimer(withTimeInterval: max(0, expirationDate.timeIntervalSinceNow), repeats: false) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                self.settingsStore.normalizeExpiredPauseIfNeeded()
                self.syncNow(reason: "pause expired", force: true)
            }
        }
    }

    private func highestPriorityMatchingProfile(runningBundleIDs: Set<String>) -> FocusProfile? {
        settingsStore.profiles.first { profile in
            profile.isEnabled
                && !profile.watchedBundleIdentifiers.isEmpty
                && !runningBundleIDs.isDisjoint(with: Set(profile.watchedBundleIdentifiers))
        }
    }

    private func runningWatchedBundleIdentifiers() -> [String] {
        let watched = Set(settingsStore.profiles.flatMap(\.watchedBundleIdentifiers))
        guard !watched.isEmpty else {
            return []
        }

        return Array(Set(workspace.runningApplications.compactMap { app in
            guard let bundleIdentifier = app.bundleIdentifier, watched.contains(bundleIdentifier) else {
                return nil
            }

            return bundleIdentifier
        })).sorted()
    }

    private func profile(id: String?) -> FocusProfile? {
        guard let id else {
            return nil
        }

        return settingsStore.profiles.first { $0.id == id }
    }

    private func readActualStatus(modeIdentifier: String) -> (status: FocusStatus, errorMessage: String?) {
        do {
            return (try focusBackend.getStatus(modeIdentifier: modeIdentifier), nil)
        } catch {
            logBackendError(error)
            let message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            return (.unknown, message)
        }
    }

    private func currentActualStatusForSnapshot(profile: FocusProfile? = nil) -> (status: FocusStatus, errorMessage: String?) {
        let modeIdentifier = profile?.selectedFocusModeIdentifier
            ?? settingsStore.selectedProfile?.selectedFocusModeIdentifier
            ?? FocusMode.defaultWork.modeIdentifier
        return readActualStatus(modeIdentifier: modeIdentifier)
    }

    private func refreshSnapshot(
        state: FocusKeeperAutomationState,
        activeProfile: FocusProfile?,
        runningBundleIDs: [String],
        actualStatus: (status: FocusStatus, errorMessage: String?),
        errorMessage: String?
    ) {
        snapshot = AppWatcherSnapshot(
            state: errorMessage == nil ? state : .error,
            watchedAppsRunningCount: runningBundleIDs.count,
            runningWatchedBundleIdentifiers: runningBundleIDs,
            desiredFocusEnabled: activeProfile != nil,
            actualFocusStatus: actualStatus.status,
            activeProfileID: activeProfile?.id,
            activeProfileName: activeProfile?.name,
            selectedFocusModeIdentifier: activeProfile?.selectedFocusModeIdentifier ?? settingsStore.selectedProfile?.selectedFocusModeIdentifier,
            pendingOffProfileID: pendingOffContext?.profile.id,
            pendingOffDueDate: pendingOffContext?.dueDate,
            pauseState: settingsStore.pauseState,
            lastBackendAction: lastBackendAction,
            lastBackendActionDate: lastBackendActionDate,
            lastSleepWakeSyncDate: lastSleepWakeSyncDate,
            errorMessage: errorMessage ?? actualStatus.errorMessage
        )
    }

    private func handleError(_ error: Error, activeProfile: FocusProfile?, runningBundleIDs: [String]) {
        logBackendError(error)
        let message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        refreshSnapshot(
            state: .error,
            activeProfile: activeProfile,
            runningBundleIDs: runningBundleIDs,
            actualStatus: (.unknown, message),
            errorMessage: message
        )
    }

    private func recordBackendAction(_ action: String) {
        lastBackendAction = action
        lastBackendActionDate = Date()
        logger.info("backend action recorded; action=\(action)")
    }

    private func logBackendError(_ error: Error) {
        let message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        logger.log(error, context: "AppWatcher")
        NSLog("FocusKeeper AppWatcher backend error: \(message)")
    }
}
