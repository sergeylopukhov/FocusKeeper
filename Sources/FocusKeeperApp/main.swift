import AppKit
import Combine
import FocusBackend

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var menuBarController: MenuBarController?
    private var settingsStore: SettingsStore?
    private var fullDiskAccessChecker: FullDiskAccessChecker?
    private var focusModeDiscovery: FocusModeDiscovery?
    private var launchAtLoginManager: LaunchAtLoginManager?
    private var appWatcher: AppWatcher?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        configureMainMenu()
        let settingsStore = SettingsStore()
        let focusBackend = FocusBackend()
        let fullDiskAccessChecker = FullDiskAccessChecker()
        let focusModeDiscovery = FocusModeDiscovery(settingsStore: settingsStore)
        let launchAtLoginManager = LaunchAtLoginManager()
        self.settingsStore = settingsStore
        self.fullDiskAccessChecker = fullDiskAccessChecker
        self.focusModeDiscovery = focusModeDiscovery
        self.launchAtLoginManager = launchAtLoginManager
        launchAtLoginManager.refresh(settingsStore: settingsStore)

        let menuBarController = MenuBarController(
            focusBackend: focusBackend,
            settingsStore: settingsStore,
            fullDiskAccessChecker: fullDiskAccessChecker,
            focusModeDiscovery: focusModeDiscovery,
            launchAtLoginManager: launchAtLoginManager
        )
        self.menuBarController = menuBarController

        let appWatcher = AppWatcher(
            settingsStore: settingsStore,
            focusBackend: focusBackend,
            focusModeDiscovery: focusModeDiscovery
        ) { snapshot in
            menuBarController.updateWatcherSnapshot(snapshot)
        }
        self.appWatcher = appWatcher
        appWatcher.start()

        if fullDiskAccessChecker.check().needsUserAction {
            menuBarController.showSettings()
        } else {
            _ = focusModeDiscovery.refresh()
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    func applicationWillTerminate(_ notification: Notification) {
        appWatcher?.stop()
    }

    @MainActor
    private func configureMainMenu() {
        let mainMenu = NSMenu()

        let appMenuItem = NSMenuItem()
        let appMenu = NSMenu(title: "FocusKeeper")
        let quitItem = NSMenuItem(
            title: "Quit FocusKeeper",
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q"
        )
        quitItem.target = NSApp
        appMenu.addItem(quitItem)
        appMenuItem.submenu = appMenu
        mainMenu.addItem(appMenuItem)

        let windowMenuItem = NSMenuItem()
        let windowMenu = NSMenu(title: "Window")
        let closeItem = NSMenuItem(
            title: "Close Window",
            action: #selector(NSWindow.performClose(_:)),
            keyEquivalent: "w"
        )
        closeItem.target = nil
        windowMenu.addItem(closeItem)
        windowMenuItem.submenu = windowMenu
        mainMenu.addItem(windowMenuItem)

        NSApp.mainMenu = mainMenu
    }
}

let app = NSApplication.shared
let appDelegate = AppDelegate()
app.delegate = appDelegate
app.run()

@MainActor
final class MenuBarController: NSObject {
    private let statusItem: NSStatusItem
    private let menu = NSMenu()
    private let focusBackend: FocusBackend
    private let settingsStore: SettingsStore
    private let fullDiskAccessChecker: FullDiskAccessChecker
    private let focusModeDiscovery: FocusModeDiscovery
    private let launchAtLoginManager: LaunchAtLoginManager
    private var settingsWindowController: SettingsWindowController?
    private var diagnosticsWindowController: DiagnosticsWindowController?
    private var languageCancellable: AnyCancellable?
    private var menuRefreshTimer: Timer?

    private let appTitleMenuItem = NSMenuItem()
    private let activeProfileMenuItem = NSMenuItem()
    private let chooseProfileMenuItem = NSMenuItem()
    private let pendingOffMenuItem = NSMenuItem()
    private let cancelPendingOffMenuItem = NSMenuItem()
    private let statusMenuItem = NSMenuItem()
    private let permissionMenuItem = NSMenuItem()
    private let watchedAppsRunningMenuItem = NSMenuItem()
    private let desiredStateMenuItem = NSMenuItem()
    private let actualStateMenuItem = NSMenuItem()
    private let lastErrorMenuItem = NSMenuItem()
    private let diagnosticsSeparatorMenuItem = NSMenuItem.separator()
    private let toggleMenuItem = NSMenuItem()
    private let syncNowMenuItem = NSMenuItem()
    private let checkPermissionsMenuItem = NSMenuItem()
    private let pauseMenuItem = NSMenuItem()
    private let resumeMenuItem = NSMenuItem()
    private let settingsMenuItem = NSMenuItem()
    private let diagnosticsMenuItem = NSMenuItem()
    private let quitMenuItem = NSMenuItem()

    private var currentStatus: FocusStatus = .unknown
    private var watcherSnapshot = AppWatcherSnapshot(
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
    )

    private var strings: AppStrings {
        AppStrings(settingsStore.effectiveLanguage)
    }

    init(
        focusBackend: FocusBackend,
        settingsStore: SettingsStore,
        fullDiskAccessChecker: FullDiskAccessChecker,
        focusModeDiscovery: FocusModeDiscovery,
        launchAtLoginManager: LaunchAtLoginManager
    ) {
        self.focusBackend = focusBackend
        self.settingsStore = settingsStore
        self.fullDiskAccessChecker = fullDiskAccessChecker
        self.focusModeDiscovery = focusModeDiscovery
        self.launchAtLoginManager = launchAtLoginManager
        self.statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        super.init()

        configureStatusItem()
        buildMenu()
        observeLanguageChanges()
        refreshStatus()
    }

    private func configureStatusItem() {
        if let button = statusItem.button {
            button.title = ""
            button.image = FocusKeeperIcon.menuBarImage()
            button.imagePosition = .imageOnly
            button.toolTip = "FocusKeeper"
        }
    }

    private func buildMenu() {
        menu.delegate = self

        appTitleMenuItem.title = "FocusKeeper"
        appTitleMenuItem.isEnabled = false
        menu.addItem(appTitleMenuItem)

        activeProfileMenuItem.isEnabled = false
        menu.addItem(activeProfileMenuItem)

        menu.addItem(chooseProfileMenuItem)

        pendingOffMenuItem.isEnabled = false
        menu.addItem(pendingOffMenuItem)

        statusMenuItem.isEnabled = false
        menu.addItem(statusMenuItem)

        permissionMenuItem.isEnabled = false
        menu.addItem(permissionMenuItem)

        watchedAppsRunningMenuItem.isEnabled = false
        menu.addItem(watchedAppsRunningMenuItem)

        desiredStateMenuItem.isEnabled = false
        menu.addItem(desiredStateMenuItem)

        actualStateMenuItem.isEnabled = false
        menu.addItem(actualStateMenuItem)

        lastErrorMenuItem.isEnabled = false
        menu.addItem(lastErrorMenuItem)

        menu.addItem(diagnosticsSeparatorMenuItem)

        toggleMenuItem.target = self
        toggleMenuItem.action = #selector(toggleWorkFocusNow)
        menu.addItem(toggleMenuItem)

        cancelPendingOffMenuItem.target = self
        cancelPendingOffMenuItem.action = #selector(cancelPendingOff)
        menu.addItem(cancelPendingOffMenuItem)

        syncNowMenuItem.title = strings.menuSyncNow
        syncNowMenuItem.target = self
        syncNowMenuItem.action = #selector(syncNow)
        menu.addItem(syncNowMenuItem)

        configurePauseMenu()
        configureProfileMenu()
        menu.addItem(pauseMenuItem)

        resumeMenuItem.target = self
        resumeMenuItem.action = #selector(resumeFocusKeeper)
        menu.addItem(resumeMenuItem)

        checkPermissionsMenuItem.target = self
        checkPermissionsMenuItem.action = #selector(checkPermissions)
        menu.addItem(checkPermissionsMenuItem)

        settingsMenuItem.target = self
        settingsMenuItem.action = #selector(openSettings)
        settingsMenuItem.keyEquivalent = ","
        menu.addItem(settingsMenuItem)

        diagnosticsMenuItem.target = self
        diagnosticsMenuItem.action = #selector(openDiagnostics)
        menu.addItem(diagnosticsMenuItem)

        menu.addItem(.separator())

        quitMenuItem.target = self
        quitMenuItem.action = #selector(quit)
        quitMenuItem.keyEquivalent = "q"
        menu.addItem(quitMenuItem)

        statusItem.menu = menu
        updateDiagnosticsVisibility(showDiagnostics: false)
    }

    private func configurePauseMenu() {
        let submenu = NSMenu()
        submenu.addItem(makePauseItem(title: strings.menuPause15, action: #selector(pauseFor15Minutes)))
        submenu.addItem(makePauseItem(title: strings.menuPauseHour, action: #selector(pauseForOneHour)))
        submenu.addItem(makePauseItem(title: strings.menuPauseTomorrow, action: #selector(pauseUntilTomorrow)))
        submenu.addItem(makePauseItem(title: strings.menuPauseIndefinitely, action: #selector(pauseIndefinitely)))
        pauseMenuItem.submenu = submenu
    }

    private func configureProfileMenu() {
        let submenu = NSMenu()
        for profile in settingsStore.profiles {
            let item = NSMenuItem(title: profile.name.isEmpty ? strings.profilesTitle : profile.name, action: #selector(activateProfileFromMenu(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = profile.id
            item.state = profile.isEnabled ? .on : .off
            submenu.addItem(item)
        }

        chooseProfileMenuItem.submenu = submenu
    }

    private func makePauseItem(title: String, action: Selector) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = self
        return item
    }

    private func observeLanguageChanges() {
        languageCancellable = settingsStore.$languagePreference
            .sink { [weak self] _ in
                Task { @MainActor in
                    self?.refreshMenuTitles()
                }
            }
    }

    func updateWatcherSnapshot(_ snapshot: AppWatcherSnapshot) {
        watcherSnapshot = snapshot
        refreshMenuTitles()
        updateMenuBarIcon()
    }

    func showSettings() {
        openSettings()
    }

    private func refreshStatus() {
        do {
            let mode = try focusModeDiscovery.selectedMode()
            currentStatus = try focusBackend.getStatus(modeIdentifier: mode.modeIdentifier)
        } catch {
            currentStatus = .unknown
            presentBackendError(error)
        }

        refreshMenuTitles()
    }

    private func refreshMenuTitles() {
        let actualStatus = watcherSnapshot.actualFocusStatus == .unknown
            ? currentStatus
            : watcherSnapshot.actualFocusStatus

        syncNowMenuItem.title = strings.menuSyncNow
        checkPermissionsMenuItem.title = strings.menuCheckPermissions
        settingsMenuItem.title = strings.menuSettings
        diagnosticsMenuItem.title = strings.menuDiagnostics
        quitMenuItem.title = strings.menuQuit
        pauseMenuItem.title = strings.menuPause
        resumeMenuItem.title = strings.menuResume
        configurePauseMenu()
        configureProfileMenu()

        activeProfileMenuItem.title = watcherSnapshot.activeProfileName.map {
            "\(strings.menuActiveProfile): \($0)"
        } ?? strings.menuNoActiveProfile
        chooseProfileMenuItem.title = strings.chooseActiveProfile

        if let dueDate = watcherSnapshot.pendingOffDueDate {
            pendingOffMenuItem.title = "\(strings.menuPendingOff) \(strings.durationUntil(dueDate))"
            cancelPendingOffMenuItem.title = strings.menuCancelPendingOff
            pendingOffMenuItem.isHidden = false
            cancelPendingOffMenuItem.isHidden = false
        } else {
            pendingOffMenuItem.isHidden = true
            cancelPendingOffMenuItem.isHidden = true
        }

        resumeMenuItem.isHidden = !settingsStore.pauseState.isPaused
        pauseMenuItem.isHidden = settingsStore.pauseState.isPaused
        statusMenuItem.title = "\(strings.menuCurrentStatus): \(displayTitle(for: actualStatus))"
        permissionMenuItem.title = permissionTitle()
        watchedAppsRunningMenuItem.title = "\(strings.menuWatchedRunning): \(watcherSnapshot.watchedAppsRunningCount)"
        desiredStateMenuItem.title = "\(strings.menuDesired): \(watcherSnapshot.desiredFocusEnabled ? strings.menuDesiredOn : strings.menuDesiredOff)"
        actualStateMenuItem.title = "\(strings.menuActual): \(watcherSnapshot.errorMessage == nil ? shortDisplayTitle(for: actualStatus) : strings.menuPermissionError)"
        lastErrorMenuItem.title = watcherSnapshot.errorMessage.map { "\(strings.menuError): \(trimmedMenuMessage($0))" } ?? "\(strings.menuError): \(strings.menuNoError)"
        toggleMenuItem.title = actualStatus == .enabled ? strings.menuTurnOffNow : strings.menuTurnOnNow
        updateMenuBarIcon()
    }

    private func updateDiagnosticsVisibility(showDiagnostics: Bool) {
        appTitleMenuItem.isHidden = !showDiagnostics
        statusMenuItem.isHidden = !showDiagnostics
        permissionMenuItem.isHidden = !showDiagnostics
        watchedAppsRunningMenuItem.isHidden = !showDiagnostics
        desiredStateMenuItem.isHidden = !showDiagnostics
        actualStateMenuItem.isHidden = !showDiagnostics
        lastErrorMenuItem.isHidden = !showDiagnostics
        diagnosticsSeparatorMenuItem.isHidden = !showDiagnostics
    }

    @objc private func toggleWorkFocusNow() {
        do {
            let mode = try focusModeDiscovery.selectedMode()
            if currentStatus == .enabled {
                try focusBackend.disableWorkFocus()
            } else {
                try focusBackend.enableFocus(modeIdentifier: mode.modeIdentifier)
            }

            refreshStatus()
        } catch {
            currentStatus = .unknown
            refreshStatus()
            presentBackendError(error)
            showErrorAlert(error)
        }
    }

    @objc private func cancelPendingOff() {
        NotificationCenter.default.post(name: .focusKeeperCancelPendingOffRequested, object: nil)
    }

    @objc private func activateProfileFromMenu(_ sender: NSMenuItem) {
        guard let profileID = sender.representedObject as? String else {
            return
        }

        settingsStore.activateProfile(id: profileID)
        syncNow()
    }

    @objc private func openSettings() {
        if settingsWindowController == nil {
            settingsWindowController = SettingsWindowController(
                settingsStore: settingsStore,
                fullDiskAccessChecker: fullDiskAccessChecker,
                focusModeDiscovery: focusModeDiscovery,
                launchAtLoginManager: launchAtLoginManager
            )
        }

        settingsWindowController?.showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc private func openDiagnostics() {
        if diagnosticsWindowController == nil {
            diagnosticsWindowController = DiagnosticsWindowController(
                settingsStore: settingsStore,
                fullDiskAccessChecker: fullDiskAccessChecker,
                focusModeDiscovery: focusModeDiscovery,
                snapshotProvider: { [weak self] in
                    self?.watcherSnapshot ?? AppWatcherSnapshot(
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
                    )
                }
            )
        }

        diagnosticsWindowController?.showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc private func checkPermissions() {
        let status = fullDiskAccessChecker.check()
        refreshMenuTitles()

        if status.needsUserAction {
            showSettings()
        } else {
            _ = focusModeDiscovery.refresh()
        }
    }

    @objc private func syncNow() {
        NotificationCenter.default.post(
            name: .focusKeeperSyncNowRequested,
            object: nil,
            userInfo: ["force": true]
        )
    }

    @objc private func pauseFor15Minutes() {
        settingsStore.setPauseState(.until(Date().addingTimeInterval(15 * 60)))
    }

    @objc private func pauseForOneHour() {
        settingsStore.setPauseState(.until(Date().addingTimeInterval(60 * 60)))
    }

    @objc private func pauseUntilTomorrow() {
        let calendar = Calendar.current
        let tomorrowStart = calendar.startOfDay(for: calendar.date(byAdding: .day, value: 1, to: Date()) ?? Date().addingTimeInterval(24 * 60 * 60))
        settingsStore.setPauseState(.until(tomorrowStart))
    }

    @objc private func pauseIndefinitely() {
        settingsStore.setPauseState(.indefinite)
    }

    @objc private func resumeFocusKeeper() {
        settingsStore.resumeAutomation()
        syncNow()
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }

    private func presentBackendError(_ error: Error) {
        let message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        watcherSnapshot.errorMessage = message
        FocusKeeperLogger.shared.log(error, context: "MenuBarController")
        NSLog("FocusKeeper backend error: \(message)")
    }

    private func trimmedMenuMessage(_ message: String) -> String {
        let maxLength = 96
        guard message.count > maxLength else {
            return message
        }

        return String(message.prefix(maxLength)) + "..."
    }

    private func showErrorAlert(_ error: Error) {
        let message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        let alert = NSAlert()
        alert.messageText = strings.alertUpdateFailed
        alert.informativeText = message
        alert.alertStyle = .warning
        alert.addButton(withTitle: strings.alertOK)

        if case FocusBackendError.permissionDenied = error {
            alert.addButton(withTitle: strings.openFullDiskSettings)
            if alert.runModal() == .alertSecondButtonReturn {
                fullDiskAccessChecker.openFullDiskAccessSettings()
            }
        } else {
            alert.runModal()
        }
    }

    private func updateMenuBarIcon() {
        guard let button = statusItem.button else {
            return
        }

        let iconState: FocusKeeperIcon.MenuState
        switch watcherSnapshot.state {
        case .paused:
            iconState = .paused
        case .error:
            iconState = .error
        case .pendingOff:
            iconState = .pending
        case .active:
            iconState = .active
        case .idle:
            iconState = .idle
        }

        button.image = FocusKeeperIcon.menuBarImage(state: iconState)
        switch watcherSnapshot.state {
        case .idle, .paused:
            button.alphaValue = 0.55
        default:
            button.alphaValue = 1.0
        }
    }

    private func permissionTitle() -> String {
        switch fullDiskAccessChecker.status {
        case .allowed:
            return strings.permissionsOK
        case .denied:
            return strings.permissionsNeeded
        case .unknown:
            return strings.permissionsUnknown
        }
    }

    private func displayTitle(for status: FocusStatus) -> String {
        switch status {
        case .enabled:
            return strings.focusEnabled
        case .disabled:
            return strings.focusDisabled
        case .unknown:
            return strings.focusUnknown
        }
    }

    private func shortDisplayTitle(for status: FocusStatus) -> String {
        switch status {
        case .enabled:
            return strings.onShort
        case .disabled:
            return strings.offShort
        case .unknown:
            return strings.unknownShort
        }
    }
}

extension Notification.Name {
    static let focusKeeperSyncNowRequested = Notification.Name("FocusKeeperSyncNowRequested")
    static let focusKeeperCancelPendingOffRequested = Notification.Name("FocusKeeperCancelPendingOffRequested")
    static let focusKeeperModeSelectionChanged = Notification.Name("FocusKeeperModeSelectionChanged")
}

extension MenuBarController: NSMenuDelegate {
    nonisolated func menuWillOpen(_ menu: NSMenu) {
        let showDiagnostics = NSEvent.modifierFlags.contains(.control)

        Task { @MainActor in
            updateDiagnosticsVisibility(showDiagnostics: showDiagnostics)
            refreshStatus()
            menuRefreshTimer?.invalidate()
            if watcherSnapshot.pendingOffDueDate != nil {
                menuRefreshTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
                    Task { @MainActor in
                        self?.refreshMenuTitles()
                    }
                }
            }
        }
    }

    nonisolated func menuDidClose(_ menu: NSMenu) {
        Task { @MainActor in
            menuRefreshTimer?.invalidate()
            menuRefreshTimer = nil
        }
    }
}
