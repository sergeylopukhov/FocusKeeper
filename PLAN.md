# FocusKeeper Implementation Plan

## Current Project State

The project folder is currently empty except for Git metadata. The first implementation step should create a native macOS app structure from scratch.

## Product Goal

FocusKeeper is a native macOS menu-bar utility that keeps the macOS Focus mode "Работа" enabled while selected applications are running. It must not depend on Apple Shortcuts.

The experimentally verified Focus mode identifier for "Работа" on this Mac is:

```text
com.apple.focus.work
```

The backend must manage Focus by safely editing:

```text
~/Library/DoNotDisturb/DB/Assertions.json
```

## Proposed Project Structure

```text
FocusKeeper/
  FocusKeeper.xcodeproj
  FocusKeeper/
    FocusKeeperApp.swift
    AppDelegate.swift
    MenuBar/
      MenuBarController.swift
      StatusMenuBuilder.swift
    Focus/
      FocusBackend.swift
      FocusAssertionRecord.swift
      FocusAssertionsFile.swift
      FocusBackendError.swift
    AppWatching/
      AppWatcher.swift
      RunningApplicationProvider.swift
      WatchedApp.swift
    Settings/
      SettingsStore.swift
      AppSettings.swift
    Permissions/
      FullDiskAccessChecker.swift
      PermissionInstructionsView.swift
    UI/
      SettingsWindow.swift
      WatchedAppsView.swift
      DiagnosticsView.swift
    Utilities/
      AtomicFileWriter.swift
      ShellCommandRunner.swift
      Logger.swift
  FocusKeeperTests/
    FocusBackendTests.swift
    AppWatcherTests.swift
    SettingsStoreTests.swift
```

The initial app should be small and local-first. A full package split is not necessary until the app grows, but the boundaries above should be reflected in the source folders.

## App Architecture

FocusKeeper should be a native macOS menu-bar app using Swift, SwiftUI, and AppKit where needed.

Core components:

- `FocusKeeperApp`: application entry point.
- `AppDelegate`: owns app lifecycle, menu-bar status item, app watcher, settings store, and focus backend.
- `MenuBarController`: presents current state and quick actions from the menu bar.
- `SettingsWindow`: allows the user to choose watched apps and view permission/status diagnostics.
- `AppWatcher`: detects whether any selected apps are currently running.
- `FocusBackend`: reads and writes `Assertions.json`, updates timestamps, and restarts only the required system agents.
- `SettingsStore`: persists selected app bundle identifiers and user preferences.

Recommended runtime flow:

1. App starts from the menu bar.
2. Settings are loaded.
3. `AppWatcher` begins observing running application changes.
4. When at least one watched app is running, `FocusBackend.enableWorkFocus()` is called.
5. When no watched apps are running, `FocusBackend.disableWorkFocus()` is called.
6. Menu-bar state updates show whether FocusKeeper is active, blocked by permissions, or idle.

## FocusBackend Design

`FocusBackend` is responsible for all direct interaction with the Do Not Disturb database file. No UI code should modify `Assertions.json` directly.

Responsibilities:

- Resolve the target path:

```text
~/Library/DoNotDisturb/DB/Assertions.json
```

- Decode the existing JSON into a typed or safely structured representation.
- Preserve unrelated top-level fields and unknown fields.
- Update `header.timestamp` using Apple absolute time:

```text
Date().timeIntervalSince1970 - 978307200
```

- Enable Focus by ensuring `data[0].storeAssertionRecords` contains one active record whose:

```text
assertionDetailsModeIdentifier = "com.apple.focus.work"
```

- Disable Focus by setting:

```text
data[0].storeAssertionRecords = []
```

- Write the file atomically.
- Create a timestamped backup before every write.
- Restart only the required macOS agents after a successful write.

Enable restart commands:

```sh
killall donotdisturbd 2>/dev/null || true
killall NotificationCenter 2>/dev/null || true
```

Disable restart commands:

```sh
killall donotdisturbd 2>/dev/null || true
killall usernotificationsd 2>/dev/null || true
killall usernoted 2>/dev/null || true
```

Important constraint:

```text
Do not kill ControlCenter.
```

Suggested public API:

```swift
protocol FocusBackendProtocol {
    func enableWorkFocus() throws
    func disableWorkFocus() throws
    func readCurrentState() throws -> FocusBackendState
}
```

The backend should be idempotent. Calling `enableWorkFocus()` repeatedly should not append duplicate active records. Calling `disableWorkFocus()` repeatedly should leave the file valid and unchanged except when a timestamp update is intentionally needed.

### Assertion Record Shape

The exact assertion record should be based on the currently observed structure in `Assertions.json` on this Mac before implementation. The implementation should avoid inventing fields blindly.

Recommended approach:

1. Read the existing file.
2. Capture a known-good active assertion record from the experimental backend or current system state if available.
3. Store the minimum necessary record structure in code or a fixture.
4. Only vary fields that must change, especially timestamp-like values and `assertionDetailsModeIdentifier`.

If no known-good record is present during implementation, create a diagnostic command or developer-only export step before finalizing the backend.

## AppWatcher Design

`AppWatcher` tracks whether selected apps are running.

Recommended sources:

- `NSWorkspace.shared.runningApplications` for initial state.
- `NSWorkspace.didLaunchApplicationNotification`.
- `NSWorkspace.didTerminateApplicationNotification`.

Watched apps should be identified primarily by bundle identifier, not display name, because app names can be localized or duplicated.

Suggested model:

```swift
struct WatchedApp: Codable, Identifiable, Equatable {
    var id: String { bundleIdentifier }
    let bundleIdentifier: String
    let displayName: String
    let path: String?
}
```

Suggested public API:

```swift
protocol AppWatcherProtocol {
    var isAnyWatchedAppRunning: Bool { get }
    var runningWatchedApps: [WatchedApp] { get }
    func start()
    func stop()
    func setWatchedApps(_ apps: [WatchedApp])
}
```

The watcher should debounce state changes before calling `FocusBackend`. Short debounce windows, such as 0.5 to 1.0 seconds, will avoid repeated writes when several apps launch or quit at once.

State transitions should be explicit:

- `inactive`: no watched apps running.
- `active`: at least one watched app running and Focus should be enabled.
- `permissionError`: Focus file cannot be read or written.
- `backendError`: JSON update or restart command failed.

## Settings Storage

Use `UserDefaults` for the first version. It is sufficient for:

- watched app bundle identifiers;
- watched app display names;
- watched app paths, if known;
- launch-at-login preference;
- last backend status or diagnostic message;
- optional setting for whether FocusKeeper disables Focus on quit.

Suggested settings model:

```swift
struct AppSettings: Codable {
    var watchedApps: [WatchedApp]
    var launchAtLogin: Bool
    var disableFocusOnQuit: Bool
}
```

Use a dedicated `SettingsStore` wrapper rather than reading `UserDefaults` throughout the app. This keeps future migration to a plist or app group container straightforward.

## Full Disk Access Requirement

FocusKeeper needs Full Disk Access because it must read and write:

```text
~/Library/DoNotDisturb/DB/Assertions.json
```

The app should detect missing access by attempting a harmless read of the file and reporting a clear permission state in the menu and settings window.

The UI should instruct the user to grant Full Disk Access in:

```text
System Settings > Privacy & Security > Full Disk Access
```

The app can open the Privacy & Security settings pane, but the user must manually grant permission. FocusKeeper should fail closed when access is missing: no partial writes, no repeated restart attempts, and no silent state changes.

## Safety Precautions and Backups

The backend edits a private macOS data file, so safety is a first-class requirement.

Precautions:

- Never modify the file unless JSON decoding and validation succeeded.
- Preserve unknown fields.
- Require `data` to contain at least one element before writing.
- Verify that `data[0]` can hold `storeAssertionRecords`.
- Write through a temporary file and atomically replace the original.
- Preserve file permissions and ownership where possible.
- Create a timestamped backup before every write.
- Keep backups in a local app-controlled backup directory, for example:

```text
~/Library/Application Support/FocusKeeper/Backups/
```

- Limit retained backups, for example the latest 20 files.
- Log backend operations without logging unrelated private notification data.
- Do not kill `ControlCenter`.
- Do not call Apple Shortcuts.
- Do not use broad process restarts beyond the exact restart commands listed in this plan.

Suggested backup filename:

```text
Assertions-YYYYMMDD-HHMMSS.json
```

Failure behavior:

- If backup creation fails, do not write.
- If atomic write fails, leave the original file untouched.
- If restart commands fail, report a warning but keep the written file and surface diagnostics.
- If the file format is unexpectedly different, stop and show a diagnostic instead of guessing.

## Implementation Phases

### Phase 1: Project Skeleton

- Create a native macOS Swift project.
- Configure it as a menu-bar utility with no main dock window by default.
- Add source folders matching the planned architecture.
- Add basic logging and error types.

### Phase 2: Backend Read and Diagnostics

- Implement `FocusBackend` read-only parsing.
- Add diagnostics for file existence, read access, JSON shape, current timestamp, and current assertion records.
- Add tests using fixture JSON files.
- Add Full Disk Access detection through real file read behavior.

### Phase 3: Safe Backend Writes

- Implement backups.
- Implement atomic writes.
- Implement Apple absolute timestamp updates.
- Implement idempotent enable/disable operations.
- Implement the exact restart command sets for enable and disable.
- Add tests for JSON preservation, duplicate prevention, timestamp update, and emptying assertion records.

### Phase 4: App Watching

- Implement `AppWatcher` using `NSWorkspace`.
- Add watched app selection and persistence.
- Add debounced state transitions.
- Add tests around launch/terminate event handling using mock providers.

### Phase 5: Menu-Bar UI

- Add status item and menu.
- Show active, idle, and error states.
- Add commands for opening settings, enabling/disabling manually for diagnostics, and quitting.
- Add settings UI for selecting watched apps.

### Phase 6: Permission and Recovery UX

- Add Full Disk Access instructions.
- Add a button to open the relevant System Settings pane.
- Add backup listing or "restore latest backup" only if needed after the backend proves stable.
- Add clear diagnostics for malformed JSON, permission denial, and restart command failures.

### Phase 7: Packaging and Polish

- Add app icon and display name `FocusKeeper`.
- Configure launch at login if desired.
- Review sandboxing and signing constraints. The app likely cannot be sandboxed if it must edit `~/Library/DoNotDisturb/DB/Assertions.json`.
- Build a release archive.
- Test on this Mac with the verified Focus identifier `com.apple.focus.work`.

## Launch at Login

The current SwiftPM executable target is not yet packaged as a signed `.app` bundle with the metadata needed to use `SMAppService` cleanly. Until the project moves to a bundled app target, FocusKeeper uses a user LaunchAgent fallback:

```text
~/Library/LaunchAgents/com.focuskeeper.app.plist
```

The LaunchAgent points at the current FocusKeeper executable path and starts the app silently in menu-bar accessory mode. When the app is later converted to a proper signed macOS app bundle, replace this fallback with the modern ServiceManagement `SMAppService` registration flow.

## Non-Goals for Initial Version

- No Apple Shortcuts dependency.
- No iCloud sync.
- No support for multiple Focus modes until the single verified mode is stable.
- No killing `ControlCenter`.
- No background daemon or privileged helper unless the simple menu-bar app cannot reliably access the required file with Full Disk Access.
