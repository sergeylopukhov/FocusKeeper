import AppKit
import SwiftUI

@MainActor
final class SettingsWindowController: NSWindowController {
    init(
        settingsStore: SettingsStore,
        fullDiskAccessChecker: FullDiskAccessChecker,
        focusModeDiscovery: FocusModeDiscovery,
        launchAtLoginManager: LaunchAtLoginManager
    ) {
        let rootView = SettingsView(
            settingsStore: settingsStore,
            fullDiskAccessChecker: fullDiskAccessChecker,
            focusModeDiscovery: focusModeDiscovery,
            launchAtLoginManager: launchAtLoginManager
        )

        let hostingController = NSHostingController(rootView: rootView)
        let window = NSWindow(contentViewController: hostingController)
        window.title = "FocusKeeper Settings"
        window.setContentSize(NSSize(width: 860, height: 720))
        window.minSize = NSSize(width: 760, height: 620)
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
        window.isReleasedWhenClosed = false
        window.center()

        super.init(window: window)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}
