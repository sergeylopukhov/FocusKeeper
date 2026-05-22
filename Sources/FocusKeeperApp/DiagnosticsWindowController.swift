import AppKit
import SwiftUI

@MainActor
final class DiagnosticsWindowController: NSWindowController {
    init(
        settingsStore: SettingsStore,
        fullDiskAccessChecker: FullDiskAccessChecker,
        focusModeDiscovery: FocusModeDiscovery,
        snapshotProvider: @escaping () -> AppWatcherSnapshot
    ) {
        let rootView = DiagnosticsView(
            settingsStore: settingsStore,
            fullDiskAccessChecker: fullDiskAccessChecker,
            focusModeDiscovery: focusModeDiscovery,
            snapshotProvider: snapshotProvider
        )

        let hostingController = NSHostingController(rootView: rootView)
        let window = NSWindow(contentViewController: hostingController)
        window.title = "FocusKeeper Diagnostics"
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

private struct DiagnosticsView: View {
    @ObservedObject var settingsStore: SettingsStore
    @ObservedObject var fullDiskAccessChecker: FullDiskAccessChecker
    @ObservedObject var focusModeDiscovery: FocusModeDiscovery
    let snapshotProvider: () -> AppWatcherSnapshot

    @State private var rows: [DiagnosticsRow] = []
    @State private var report = ""

    private let fileManager = FileManager.default

    private var strings: AppStrings {
        AppStrings(settingsStore.effectiveLanguage)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text(strings.diagnosticsTitle)
                        .font(.title2.weight(.semibold))
                    Text("FocusKeeper")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Button {
                    refresh()
                } label: {
                    Label(strings.refreshDiagnostics, systemImage: "arrow.clockwise")
                }
            }

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(rows) { row in
                        HStack(alignment: .top, spacing: 12) {
                            Text(row.label)
                                .font(.callout.weight(.medium))
                                .frame(width: 250, alignment: .leading)
                            Text(row.value)
                                .font(row.isMonospaced ? .caption.monospaced() : .callout)
                                .foregroundStyle(.secondary)
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .padding(.vertical, 8)
                        Divider()
                    }
                }
                .padding(12)
                .background(Color(nsColor: .controlBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color(nsColor: .separatorColor).opacity(0.55), lineWidth: 1))
            }

            HStack(spacing: 10) {
                Button {
                    open(url: logURL)
                } label: {
                    Label(strings.openLogFile, systemImage: "doc.text")
                }

                Button {
                    open(url: backupFolderURL)
                } label: {
                    Label(strings.openBackupFolder, systemImage: "folder")
                }

                Button {
                    fullDiskAccessChecker.openFullDiskAccessSettings()
                } label: {
                    Label(strings.openFullDiskSettings, systemImage: "gearshape")
                }

                Spacer()

                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(report, forType: .string)
                } label: {
                    Label(strings.copyDiagnostics, systemImage: "doc.on.doc")
                }
                .keyboardShortcut("c", modifiers: [.command])
            }
        }
        .padding(20)
        .frame(minWidth: 760, minHeight: 620)
        .onAppear(perform: refresh)
    }

    private func refresh() {
        _ = fullDiskAccessChecker.check()
        _ = focusModeDiscovery.refresh()

        let snapshot = snapshotProvider()
        let selectedProfile = settingsStore.selectedProfile
        let selectedModeName = selectedProfile.flatMap { profile in
            focusModeDiscovery.modes.first { $0.modeIdentifier == profile.selectedFocusModeIdentifier }
        }.map { strings.focusModeName($0) } ?? strings.none

        let generatedRows = [
            DiagnosticsRow(strings.appVersion, appVersion),
            DiagnosticsRow(strings.macOSVersion, ProcessInfo.processInfo.operatingSystemVersionString),
            DiagnosticsRow(strings.fullDiskAccessStatus, fullDiskAccessChecker.status.message),
            DiagnosticsRow(strings.assertionsPath, assertionsURL.path, isMonospaced: true),
            DiagnosticsRow(strings.assertionsReadable, readable(assertionsURL) ? strings.yes : strings.no),
            DiagnosticsRow(strings.assertionsWritable, fileManager.isWritableFile(atPath: assertionsURL.path) ? strings.yes : strings.no),
            DiagnosticsRow(strings.modesPath, modeConfigurationsURL.path, isMonospaced: true),
            DiagnosticsRow(strings.modesReadable, readable(modeConfigurationsURL) ? strings.yes : strings.no),
            DiagnosticsRow(strings.discoveredModes, "\(focusModeDiscovery.modes.count)"),
            DiagnosticsRow(strings.selectedProfile, selectedProfile?.name ?? strings.none),
            DiagnosticsRow(strings.selectedFocusMode, "\(selectedModeName) / \(selectedProfile?.selectedFocusModeIdentifier ?? strings.none)", isMonospaced: true),
            DiagnosticsRow(strings.activeProfile, snapshot.activeProfileName ?? strings.none),
            DiagnosticsRow(strings.menuWatchedRunning, "\(snapshot.watchedAppsRunningCount)"),
            DiagnosticsRow(strings.runningWatchedApps, snapshot.runningWatchedBundleIdentifiers.isEmpty ? strings.none : snapshot.runningWatchedBundleIdentifiers.joined(separator: "\n"), isMonospaced: true),
            DiagnosticsRow(strings.menuActual, snapshot.actualFocusStatus.rawValue),
            DiagnosticsRow(strings.desiredFocusState, snapshot.desiredFocusEnabled ? strings.onShort : strings.offShort),
            DiagnosticsRow(strings.pendingOffStatus, pendingOffText(snapshot)),
            DiagnosticsRow(strings.pauseStatus, pauseText(settingsStore.pauseState)),
            DiagnosticsRow(strings.lastBackendAction, snapshot.lastBackendAction ?? strings.none),
            DiagnosticsRow(strings.lastBackendActionTime, formatted(snapshot.lastBackendActionDate)),
            DiagnosticsRow(strings.lastSleepWakeSync, formatted(snapshot.lastSleepWakeSyncDate)),
            DiagnosticsRow(strings.lastError, snapshot.errorMessage ?? strings.none),
            DiagnosticsRow(strings.logFilePath, logURL.path, isMonospaced: true),
            DiagnosticsRow(strings.backupFolderPath, backupFolderURL.path, isMonospaced: true)
        ]

        rows = generatedRows
        report = generatedRows.map { "\($0.label): \($0.value)" }.joined(separator: "\n")
    }

    private var appVersion: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String
        return [version, build].compactMap { $0 }.joined(separator: " ")
    }

    private var homeURL: URL {
        fileManager.homeDirectoryForCurrentUser
    }

    private var assertionsURL: URL {
        homeURL
            .appendingPathComponent("Library")
            .appendingPathComponent("DoNotDisturb")
            .appendingPathComponent("DB")
            .appendingPathComponent("Assertions.json")
    }

    private var modeConfigurationsURL: URL {
        homeURL
            .appendingPathComponent("Library")
            .appendingPathComponent("DoNotDisturb")
            .appendingPathComponent("DB")
            .appendingPathComponent("ModeConfigurations.json")
    }

    private var logURL: URL {
        homeURL
            .appendingPathComponent("Library")
            .appendingPathComponent("Logs")
            .appendingPathComponent("FocusKeeper.log")
    }

    private var backupFolderURL: URL {
        homeURL
            .appendingPathComponent("Library")
            .appendingPathComponent("Application Support")
            .appendingPathComponent("FocusKeeper")
            .appendingPathComponent("Backups")
    }

    private func readable(_ url: URL) -> Bool {
        (try? Data(contentsOf: url)) != nil
    }

    private func formatted(_ date: Date?) -> String {
        guard let date else {
            return strings.none
        }

        return DateFormatter.localizedString(from: date, dateStyle: .medium, timeStyle: .medium)
    }

    private func pendingOffText(_ snapshot: AppWatcherSnapshot) -> String {
        guard let dueDate = snapshot.pendingOffDueDate else {
            return strings.none
        }

        return "\(strings.menuPendingOff) \(strings.durationUntil(dueDate))"
    }

    private func pauseText(_ pauseState: PauseState) -> String {
        switch pauseState {
        case .none:
            return strings.automationRunning
        case .indefinite:
            return strings.menuPaused
        case .until(let date):
            return "\(strings.menuPaused) \(DateFormatter.localizedString(from: date, dateStyle: .medium, timeStyle: .short))"
        }
    }

    private func open(url: URL) {
        NSWorkspace.shared.open(url)
    }
}

private struct DiagnosticsRow: Identifiable {
    let id = UUID()
    let label: String
    let value: String
    let isMonospaced: Bool

    init(_ label: String, _ value: String, isMonospaced: Bool = false) {
        self.label = label
        self.value = value
        self.isMonospaced = isMonospaced
    }
}
