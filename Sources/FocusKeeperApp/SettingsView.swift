import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct SettingsView: View {
    @ObservedObject var settingsStore: SettingsStore
    @ObservedObject var fullDiskAccessChecker: FullDiskAccessChecker
    @ObservedObject var focusModeDiscovery: FocusModeDiscovery
    @ObservedObject var launchAtLoginManager: LaunchAtLoginManager

    @State private var manualBundleIdentifier = ""
    @State private var customOffDelaySeconds = "120"

    private var strings: AppStrings {
        AppStrings(settingsStore.effectiveLanguage)
    }

    private var selectedProfile: FocusProfile? {
        settingsStore.selectedProfile
    }

    private var selectedMode: FocusMode? {
        guard let selectedProfile else {
            return nil
        }

        return focusModeDiscovery.modes.first {
            $0.modeIdentifier == selectedProfile.selectedFocusModeIdentifier
        }
    }

    private var selectedApps: [SelectedAppInfo] {
        (selectedProfile?.watchedBundleIdentifiers ?? [])
            .map(SelectedAppInfo.init(bundleIdentifier:))
            .sorted {
                $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending
            }
    }

    var body: some View {
        HStack(spacing: 0) {
            profileSidebar

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    header

                    if fullDiskAccessChecker.status.needsUserAction {
                        fullDiskAccessPanel
                    }

                    if settingsStore.pauseState.isPaused {
                        InlineMessage(
                            systemImage: "pause.circle.fill",
                            text: strings.automationPaused,
                            tone: .warning
                        )
                    }

                    if selectedProfile != nil {
                        profileEditor
                    } else {
                        EmptyState(
                            systemImage: "rectangle.stack.badge.plus",
                            title: strings.noSelectedApps,
                            message: strings.profilesSubtitle
                        )
                    }

                    globalSettings
                }
                .padding(24)
            }
            .background(AppTheme.windowBackground)
        }
        .frame(minWidth: 980, minHeight: 720)
    }

    private var profileSidebar: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(strings.profilesTitle)
                    .font(.title3.weight(.semibold))
                Text(strings.profilePriorityHelp)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 14)
            .padding(.top, 18)

            List(selection: Binding(
                get: { settingsStore.selectedProfileID },
                set: { id in
                    if let id {
                        settingsStore.selectProfile(id: id)
                    }
                }
            )) {
                ForEach(settingsStore.profiles) { profile in
                    ProfileListRow(profile: profile, strings: strings) {
                        if settingsStore.selectedProfileID != profile.id {
                            settingsStore.selectProfile(id: profile.id)
                        }
                        settingsStore.activateProfile(id: profile.id)
                    }
                    .tag(Optional(profile.id))
                }
            }
            .listStyle(.sidebar)

            VStack(spacing: 8) {
                HStack(spacing: 8) {
                    Button {
                        settingsStore.createProfile()
                    } label: {
                        Label(strings.addProfile, systemImage: "plus")
                    }
                    .frame(maxWidth: .infinity)

                    Button {
                        confirmDeleteSelectedProfile()
                    } label: {
                        Label(strings.deleteProfile, systemImage: "trash")
                    }
                    .disabled(settingsStore.profiles.count <= 1)
                    .frame(maxWidth: .infinity)
                }

                HStack(spacing: 8) {
                    Button {
                        settingsStore.moveSelectedProfileUp()
                    } label: {
                        Label(strings.moveUp, systemImage: "chevron.up")
                    }
                    .frame(maxWidth: .infinity)

                    Button {
                        settingsStore.moveSelectedProfileDown()
                    } label: {
                        Label(strings.moveDown, systemImage: "chevron.down")
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            .controlSize(.regular)
            .padding(14)
        }
        .frame(width: 300)
        .background(Color(nsColor: .underPageBackgroundColor))
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 16) {
            Image(systemName: "scope")
                .font(.system(size: 24, weight: .medium))
                .foregroundStyle(AppTheme.accent)
                .frame(width: 34, height: 34)

            VStack(alignment: .leading, spacing: 4) {
                Text("FocusKeeper")
                    .font(.title2.weight(.semibold))
                Text(strings.headerSubtitle)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button {
                _ = focusModeDiscovery.refresh()
                _ = fullDiskAccessChecker.check()
            } label: {
                Label(strings.refresh, systemImage: "arrow.clockwise")
            }
            .controlSize(.large)
        }
    }

    private var profileEditor: some View {
        VStack(alignment: .leading, spacing: 18) {
            SectionPanel(
                icon: "slider.horizontal.3",
                title: strings.profilesTitle,
                subtitle: strings.profilesSubtitle
            ) {
                profileBasics
            }

            SectionPanel(
                icon: "scope",
                title: strings.focusModeTitle,
                subtitle: strings.focusModeSubtitle
            ) {
                focusModePicker
            }

            SectionPanel(
                icon: "app.badge.fill",
                title: strings.watchedAppsTitle,
                subtitle: strings.watchedAppsSubtitle
            ) {
                watchedAppsSection
            }

            SectionPanel(
                icon: "clock.badge.checkmark",
                title: strings.focusExitBehaviorTitle,
                subtitle: strings.focusExitBehaviorSubtitle
            ) {
                exitBehaviorSection
            }

            SectionPanel(
                icon: "hand.raised.fill",
                title: strings.manualFocusChanges,
                subtitle: strings.manualFocusChangesSubtitle
            ) {
                manualChangeSection
            }
        }
    }

    private var profileBasics: some View {
        VStack(alignment: .leading, spacing: 12) {
            TextField(strings.profileName, text: Binding(
                get: { selectedProfile?.name ?? "" },
                set: { name in
                    settingsStore.updateSelectedProfile { profile in
                        profile.name = name
                    }
                }
            ))
            .textFieldStyle(.roundedBorder)
            .frame(maxWidth: 420)

            Button {
                if let selectedProfile {
                    settingsStore.activateProfile(id: selectedProfile.id)
                }
            } label: {
                Label(strings.activateProfile, systemImage: selectedProfile?.isEnabled == true ? "checkmark.circle.fill" : "circle")
            }
            .disabled(selectedProfile?.isEnabled == true)
        }
    }

    private var focusModePicker: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center, spacing: 12) {
                Picker(strings.modePickerLabel, selection: Binding(
                    get: { selectedProfile?.selectedFocusModeIdentifier ?? FocusMode.defaultWork.modeIdentifier },
                    set: { modeIdentifier in
                        settingsStore.updateSelectedProfile { profile in
                            profile.selectedFocusModeIdentifier = modeIdentifier
                        }
                        NotificationCenter.default.post(name: .focusKeeperModeSelectionChanged, object: nil)
                    }
                )) {
                    ForEach(focusModeDiscovery.modes) { mode in
                        Text(strings.focusModeName(mode))
                            .tag(mode.modeIdentifier)
                    }
                }
                .labelsHidden()
                .frame(minWidth: 300)

                Button {
                    _ = focusModeDiscovery.refresh()
                } label: {
                    Label(strings.refreshModes, systemImage: "arrow.clockwise")
                }
            }

            if let errorMessage = focusModeDiscovery.errorMessage {
                InlineMessage(systemImage: "exclamationmark.triangle.fill", text: errorMessage, tone: .warning)
            }

            if focusModeDiscovery.modes.isEmpty {
                InlineMessage(systemImage: "moon.fill", text: strings.noModesFallback, tone: .neutral)
            } else if let selectedMode {
                HStack(spacing: 8) {
                    Text(strings.focusModeName(selectedMode))
                        .font(.callout.weight(.medium))
                    Text("\(strings.modeIdentifier):")
                        .foregroundStyle(.secondary)
                    Text(selectedMode.modeIdentifier)
                        .font(.caption.monospaced())
                        .textSelection(.enabled)
                }
                .font(.callout)
            }
        }
    }

    private var watchedAppsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(strings.selectedBundleIDs)
                    .font(.headline)

                Spacer()

                Button {
                    chooseApplications()
                } label: {
                    Label(strings.chooseApplication, systemImage: "folder.badge.plus")
                }
                .controlSize(.large)
            }

            if selectedApps.isEmpty {
                EmptyState(
                    systemImage: "app.badge",
                    title: strings.noWatchedAppsTitle,
                    message: strings.noWatchedAppsMessage
                )
            } else {
                VStack(spacing: 0) {
                    ForEach(selectedApps) { app in
                        SelectedAppRow(app: app, settingsStore: settingsStore, strings: strings)
                        if app.id != selectedApps.last?.id {
                            Divider().padding(.leading, 58)
                        }
                    }
                }
                .background(AppTheme.contentBackground)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(AppTheme.border, lineWidth: 1))
            }

            DisclosureGroup {
                manualBundleIdentifierForm
                    .padding(.top, 8)
            } label: {
                Text(strings.addManuallyTitle)
                    .font(.callout.weight(.medium))
            }
        }
    }

    private var exitBehaviorSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            Picker(strings.focusExitBehaviorPickerLabel, selection: Binding(
                get: { selectedProfile?.exitBehavior ?? .turnOff },
                set: { behavior in
                    settingsStore.updateSelectedProfile { profile in
                        profile.exitBehavior = behavior
                    }
                }
            )) {
                ForEach(FocusExitBehavior.allCases) { behavior in
                    Label(
                        strings.focusExitBehaviorTitle(behavior),
                        systemImage: behavior == .restorePrevious ? "arrow.uturn.backward.circle" : "power.circle"
                    )
                    .tag(behavior)
                }
            }
            .pickerStyle(.segmented)
            .frame(maxWidth: 460)

            InlineMessage(
                systemImage: selectedProfile?.exitBehavior == .restorePrevious ? "arrow.uturn.backward.circle.fill" : "power.circle.fill",
                text: strings.focusExitBehaviorHelp(selectedProfile?.exitBehavior ?? .turnOff),
                tone: .neutral
            )

            Divider()

            Picker(strings.offDelayTitle, selection: Binding(
                get: { selectedProfile?.offDelay ?? .immediate },
                set: { delay in
                    settingsStore.updateSelectedProfile { profile in
                        profile.offDelay = delay
                    }
                }
            )) {
                ForEach(offDelayOptions) { delay in
                    Text(strings.offDelayTitle(delay)).tag(delay)
                }
            }
            .pickerStyle(.menu)
            .frame(maxWidth: 260, alignment: .leading)

            HStack(spacing: 10) {
                TextField(strings.offDelayCustom, text: $customOffDelaySeconds)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 120)

                Button {
                    let seconds = max(0, Int(customOffDelaySeconds) ?? 0)
                    settingsStore.updateSelectedProfile { profile in
                        profile.offDelay = seconds <= 0 ? .immediate : .seconds(seconds)
                    }
                } label: {
                    Label(strings.add, systemImage: "clock.badge.plus")
                }
                .disabled((Int(customOffDelaySeconds) ?? 0) < 0)
            }
        }
    }

    private var manualChangeSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(ManualChangeBehavior.allCases) { behavior in
                OptionRow(
                    title: strings.manualChangeBehaviorTitle(behavior),
                    message: strings.manualChangeBehaviorHelp(behavior),
                    systemImage: behavior == .forceSelectedFocus ? "arrow.clockwise.circle" : "hand.raised",
                    isSelected: selectedProfile?.manualChangeBehavior == behavior
                ) {
                    settingsStore.updateSelectedProfile { profile in
                        profile.manualChangeBehavior = behavior
                    }
                }
            }
        }
    }

    private var globalSettings: some View {
        VStack(alignment: .leading, spacing: 18) {
            SectionPanel(icon: "globe", title: strings.languageTitle, subtitle: strings.languageSubtitle) {
                languageSection
            }

            SectionPanel(icon: "power.circle.fill", title: strings.launchTitle, subtitle: strings.launchSubtitle) {
                launchAtLoginSection
            }
        }
    }

    private var languageSection: some View {
        Picker(strings.languagePickerLabel, selection: Binding(
            get: { settingsStore.languagePreference },
            set: { preference in
                settingsStore.setLanguagePreference(preference)
            }
        )) {
            ForEach(AppLanguagePreference.allCases) { preference in
                Text(preference.title(in: settingsStore.effectiveLanguage)).tag(preference)
            }
        }
        .pickerStyle(.segmented)
        .frame(maxWidth: 420)
    }

    private var launchAtLoginSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Toggle(
                strings.launchAtLogin,
                isOn: Binding(
                    get: { settingsStore.launchAtLoginEnabled },
                    set: { isEnabled in
                        launchAtLoginManager.setEnabled(isEnabled, settingsStore: settingsStore)
                    }
                )
            )
            .toggleStyle(.checkbox)
            .font(.headline)

            Text(strings.launchFallbackDescription)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            if let errorMessage = launchAtLoginManager.lastErrorMessage {
                InlineMessage(systemImage: "xmark.octagon.fill", text: errorMessage, tone: .danger)
            }
        }
    }

    private var fullDiskAccessPanel: some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: "lock.trianglebadge.exclamationmark")
                .font(.system(size: 24, weight: .semibold))
                .foregroundStyle(AppTheme.warning)
                .frame(width: 32)

            VStack(alignment: .leading, spacing: 8) {
                Text(strings.fullDiskTitle).font(.headline)
                Text(strings.fullDiskBody).foregroundStyle(.primary)
                Text(strings.fullDiskPath)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)

                HStack(spacing: 10) {
                    Button {
                        fullDiskAccessChecker.openFullDiskAccessSettings()
                    } label: {
                        Label(strings.openFullDiskSettings, systemImage: "gearshape.fill")
                    }
                    .controlSize(.large)

                    Button {
                        _ = fullDiskAccessChecker.check()
                        _ = focusModeDiscovery.refresh()
                    } label: {
                        Label(strings.checkAgain, systemImage: "checkmark.circle")
                    }
                    .controlSize(.large)
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppTheme.warning.opacity(0.12))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(AppTheme.warning.opacity(0.35), lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private var manualBundleIdentifierForm: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                TextField("com.example.App", text: $manualBundleIdentifier)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(.body, design: .monospaced))
                    .onSubmit(addManualBundleIdentifier)

                Button {
                    addManualBundleIdentifier()
                } label: {
                    Label(strings.add, systemImage: "plus")
                }
                .disabled(manualBundleIdentifier.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
    }

    private var offDelayOptions: [OffDelay] {
        var options = OffDelay.presetValues
        if let selectedDelay = selectedProfile?.offDelay, !options.contains(selectedDelay) {
            options.append(selectedDelay)
        }
        return options
    }

    private func addManualBundleIdentifier() {
        settingsStore.addManualBundleIdentifier(manualBundleIdentifier)
        manualBundleIdentifier = ""
    }

    private func chooseApplications() {
        let panel = NSOpenPanel()
        panel.title = strings.chooseApplication
        panel.prompt = strings.select
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = true
        panel.allowedContentTypes = [.applicationBundle]

        guard panel.runModal() == .OK else {
            return
        }

        for url in panel.urls {
            guard
                let bundle = Bundle(url: url),
                let bundleIdentifier = bundle.bundleIdentifier
            else {
                continue
            }

            settingsStore.setSelected(true, bundleIdentifier: bundleIdentifier)
        }
    }

    private func confirmDeleteSelectedProfile() {
        let alert = NSAlert()
        alert.messageText = strings.deleteProfileTitle
        alert.informativeText = strings.deleteProfileMessage
        alert.alertStyle = .warning
        alert.addButton(withTitle: strings.delete)
        alert.addButton(withTitle: strings.cancel)

        if alert.runModal() == .alertFirstButtonReturn {
            settingsStore.deleteSelectedProfile()
        }
    }
}

private enum AppTheme {
    static let accent = Color(nsColor: .controlAccentColor)
    static let success = Color(nsColor: .systemGreen)
    static let warning = Color(nsColor: .systemOrange)
    static let danger = Color(nsColor: .systemRed)
    static let border = Color(nsColor: .separatorColor).opacity(0.55)
    static let windowBackground = Color(nsColor: .windowBackgroundColor)
    static let panelBackground = Color(nsColor: .controlBackgroundColor)
    static let contentBackground = Color(nsColor: .textBackgroundColor)
}

private enum StatusTone {
    case accent
    case success
    case warning
    case danger
    case neutral

    var color: Color {
        switch self {
        case .accent:
            return AppTheme.accent
        case .success:
            return AppTheme.success
        case .warning:
            return AppTheme.warning
        case .danger:
            return AppTheme.danger
        case .neutral:
            return .secondary
        }
    }
}

private struct ProfileListRow: View {
    let profile: FocusProfile
    let strings: AppStrings
    let onActivate: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Button(action: onActivate) {
                Image(systemName: profile.isEnabled ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(profile.isEnabled ? AppTheme.success : .secondary)
                    .frame(width: 22, height: 22)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(strings.activateProfile)

            VStack(alignment: .leading, spacing: 3) {
                Text(profile.name.isEmpty ? strings.profilesTitle : profile.name)
                    .font(.body.weight(.medium))
                Text("\(profile.watchedBundleIdentifiers.count) \(strings.overviewApps.lowercased())")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()
        }
        .frame(minHeight: 44)
    }
}

private struct SectionPanel<Content: View>: View {
    let icon: String
    let title: String
    let subtitle: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: icon)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(AppTheme.accent)
                    .frame(width: 28, height: 28)

                VStack(alignment: .leading, spacing: 3) {
                    Text(title).font(.headline)
                    Text(subtitle)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            content
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppTheme.panelBackground)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(AppTheme.border, lineWidth: 1))
    }
}

private struct InlineMessage: View {
    let systemImage: String
    let text: String
    let tone: StatusTone

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: systemImage)
                .foregroundStyle(tone.color)
                .frame(width: 18)

            Text(text)
                .font(.callout)
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(tone.color.opacity(0.10))
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }
}

private struct OptionRow: View {
    let title: String
    let message: String
    let systemImage: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 18, weight: .medium))
                    .foregroundStyle(isSelected ? AppTheme.accent : .secondary)
                    .frame(width: 24, height: 24)

                Image(systemName: systemImage)
                    .font(.system(size: 17, weight: .medium))
                    .foregroundStyle(.secondary)
                    .frame(width: 24, height: 24)

                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.callout.weight(.medium))
                        .foregroundStyle(.primary)
                    Text(message)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 0)
            }
            .padding(12)
            .frame(maxWidth: .infinity, minHeight: 58, alignment: .leading)
            .background(isSelected ? AppTheme.accent.opacity(0.10) : AppTheme.contentBackground)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(isSelected ? AppTheme.accent.opacity(0.45) : AppTheme.border, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
}

private struct EmptyState: View {
    let systemImage: String
    let title: String
    let message: String

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: systemImage)
                .font(.system(size: 30, weight: .regular))
                .foregroundStyle(.secondary)
            Text(title).font(.headline)
            Text(message)
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, minHeight: 130)
        .background(AppTheme.contentBackground)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(AppTheme.border, lineWidth: 1))
    }
}

private struct SelectedAppInfo: Identifiable {
    var id: String { bundleIdentifier }

    let bundleIdentifier: String
    let displayName: String
    let appURL: URL?
    let icon: NSImage

    init(bundleIdentifier: String) {
        self.bundleIdentifier = bundleIdentifier
        self.appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier)

        if let appURL,
           let bundle = Bundle(url: appURL) {
            self.displayName = bundle.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String
                ?? bundle.object(forInfoDictionaryKey: "CFBundleName") as? String
                ?? appURL.deletingPathExtension().lastPathComponent
            self.icon = NSWorkspace.shared.icon(forFile: appURL.path)
        } else {
            self.displayName = bundleIdentifier
            self.icon = NSWorkspace.shared.icon(for: .applicationBundle)
        }

        self.icon.size = NSSize(width: 32, height: 32)
    }
}

private struct SelectedAppRow: View {
    let app: SelectedAppInfo
    @ObservedObject var settingsStore: SettingsStore
    let strings: AppStrings

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            Image(nsImage: app.icon)
                .resizable()
                .frame(width: 34, height: 34)
                .clipShape(RoundedRectangle(cornerRadius: 7))

            VStack(alignment: .leading, spacing: 3) {
                Text(app.displayName).font(.body.weight(.medium))
                Text(app.bundleIdentifier)
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }

            Spacer()

            Button(strings.remove) {
                settingsStore.removeBundleIdentifier(app.bundleIdentifier)
            }
            .controlSize(.regular)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(minHeight: 56)
    }
}
