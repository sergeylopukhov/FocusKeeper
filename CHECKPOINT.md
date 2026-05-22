# FocusKeeper Checkpoint

Date: 2026-05-21

This checkpoint records the current verified working state after profiles, pause, diagnostics, off-delay, and sleep/wake sync were added.

## Build Command

From the project directory:

```sh
cd path/to/FocusKeeper
swift build
```

Verified result:

```text
Build complete
```

## Launch Command

Menu-bar app:

```sh
.build/debug/FocusKeeperApp
```

Debug CLI:

```sh
.build/debug/focuskeeper-debug status
.build/debug/focuskeeper-debug on
.build/debug/focuskeeper-debug off
```

## Confirmed Working Behavior

The debug CLI was verified working:

```text
.build/debug/focuskeeper-debug status -> disabled
.build/debug/focuskeeper-debug on     -> enabled
.build/debug/focuskeeper-debug off    -> disabled
```

The menu-bar app is confirmed working after the `FocusModeDiscovery` fix.

Current expected behavior:

- App launches silently in the menu bar.
- App can operate even when `ModeConfigurations.json` is not parsed into the expected schema.
- If Focus mode discovery fails, the app falls back to the verified default:

```text
name: Работа
modeIdentifier: com.apple.focus.work
```

- Settings can manage multiple rule profiles.
- Profiles are prioritized by order; the first enabled matching profile wins.
- Each profile stores Focus mode, watched bundle IDs, exit behavior, off-delay, manual-change behavior, and enabled state.
- AppWatcher enables/disables/restores Focus based on watched apps running state.
- Focus state does not depend on the active/frontmost app.
- Switching to Finder, Safari, or another unselected app does not disable Focus while a watched app is still running.
- Focus disables only when all watched apps are no longer running.
- Delayed off actions can be canceled from the menu.
- Automation can be paused without changing the current Focus state.
- Diagnostics window can copy a technical report without dumping private JSON.
- Sleep/wake events trigger delayed reconciliation when automation is not paused.
- Menu bar icon reflects idle, active, paused, error, and pending-off states.

## Verified Focus Backend Process Restarts

Enable path must restart only:

```text
donotdisturbd
NotificationCenter
```

Disable path must restart only:

```text
donotdisturbd
usernotificationsd
usernoted
```

`ControlCenter` must not be restarted or killed.

## Known Limitations

- Backend is experimental and uses private macOS Focus database files.
- Directly modifies:

```text
~/Library/DoNotDisturb/DB/Assertions.json
```

- Tested setup is macOS 26.5 with:

```text
Работа / com.apple.focus.work
```

- Requires Full Disk Access.
- `ModeConfigurations.json` may have schema variants; current app uses recursive discovery plus fallback to `com.apple.focus.work`.
- Current project is a SwiftPM executable, not a signed/notarized `.app` bundle.
- Launch at Login uses a user LaunchAgent fallback, not `SMAppService`.
- macOS updates may change private database structure or daemon behavior.
- There is no automated test suite yet.
- Profiles/config migration should be retested with real old config files before broader distribution.

## Files Most Important To Preserve

Core backend:

```text
Sources/FocusBackend/FocusBackend.swift
Sources/FocusBackend/FocusKeeperLogger.swift
```

Menu-bar app and watcher:

```text
Sources/FocusKeeperApp/main.swift
Sources/FocusKeeperApp/AppWatcher.swift
Sources/FocusKeeperApp/SettingsStore.swift
Sources/FocusKeeperApp/SettingsView.swift
Sources/FocusKeeperApp/SettingsWindowController.swift
Sources/FocusKeeperApp/DiagnosticsWindowController.swift
Sources/FocusKeeperApp/RunningAppsProvider.swift
Sources/FocusKeeperApp/FullDiskAccessChecker.swift
Sources/FocusKeeperApp/FocusModeDiscovery.swift
Sources/FocusKeeperApp/LaunchAtLoginManager.swift
```

Debug CLI:

```text
Sources/focuskeeper-debug/main.swift
```

Project/docs:

```text
Package.swift
README.md
TROUBLESHOOTING.md
PLAN.md
CHECKPOINT.md
```

## Must Not Be Changed Without Retesting

These are verified behavioral invariants. Any change here requires full manual retesting.

- Do not introduce Apple Shortcuts.
- Do not call `shortcuts run`.
- Do not introduce AppleScript.
- Do not restart or kill `ControlCenter`.
- Enable must restart only:

```text
donotdisturbd
NotificationCenter
```

- Disable must restart only:

```text
donotdisturbd
usernotificationsd
usernoted
```

- Enable must write an active assertion to:

```text
~/Library/DoNotDisturb/DB/Assertions.json
```

- Enable must use selected mode identifier as:

```text
assertionDetailsModeIdentifier
```

- Disable must clear:

```text
data[0].storeAssertionRecords
```

- Both enable and disable must update:

```text
header.timestamp
```

using Apple absolute time:

```text
Unix time - 978307200
```

- App must track watched apps by bundle identifier.
- App must not use active/frontmost app logic for Focus state.
- Focus desired state must depend only on whether selected bundle IDs are currently running.
- Writes to `Assertions.json` must remain atomic.
- Backups must remain enabled before the first write in a process session.
- Full Disk Access errors must remain visible to the user.
