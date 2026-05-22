# FocusKeeper

FocusKeeper is a native macOS menu-bar utility that keeps a selected Focus mode enabled while chosen apps are running.

It is designed for people who want a local, app-based Focus automation that does not depend on Apple Shortcuts.

## Important Warning

FocusKeeper uses an experimental direct backend. It modifies the user-owned macOS Focus database file:

```text
~/Library/DoNotDisturb/DB/Assertions.json
```

This is a private macOS data file. The format can change after macOS updates, and the app may stop working or require code changes. FocusKeeper is provided as-is.

FocusKeeper does not use Apple Shortcuts, does not run `shortcuts run`, and does not restart or kill `ControlCenter`.

## Features

- Native macOS menu-bar app.
- Focus mode discovery from the local macOS Focus configuration.
- Rule profiles with priority order.
- Per-profile watched apps stored by bundle identifier.
- Per-profile Focus mode selection.
- Per-profile exit behavior: turn Focus off or restore the previous Focus state.
- Delay before turning Focus off after watched apps quit.
- Manual Focus change behavior: respect manual changes or force the selected Focus while watched apps run.
- Pause automation for a fixed time or indefinitely.
- Diagnostics window for permissions, active profile, running watched apps, backend state, logs, and backups.
- Sleep/wake reconciliation.
- Russian and English localization.
- Debug CLI for manual backend checks.

## Screenshots

Screenshots are not included yet.

## Tested Setup

The verified setup during development:

```text
macOS 26.5
Focus mode: Работа
Mode identifier: com.apple.focus.work
```

Other Focus modes are discovered from:

```text
~/Library/DoNotDisturb/DB/ModeConfigurations.json
```

## Installation

Download the latest DMG from GitHub Releases when available, open it, and copy `FocusKeeper.app` to `/Applications`.

The app is currently unsigned or ad-hoc signed for local distribution. macOS Gatekeeper may warn that the app cannot be opened. If you build it yourself, launch the app you built and grant Full Disk Access to that exact app bundle.

## Full Disk Access

FocusKeeper requires Full Disk Access because it reads and writes local macOS Focus database files.

Enable it in:

```text
System Settings -> Privacy & Security -> Full Disk Access -> FocusKeeper
```

If permission is missing, FocusKeeper shows a clear error and does not crash.

## Build From Source

Requirements:

- macOS
- Xcode Command Line Tools
- Swift Package Manager

Build:

```sh
swift build
```

Build outputs:

```text
.build/debug/FocusKeeperApp
.build/debug/focuskeeper-debug
```

Create a local app bundle and DMG:

```sh
Scripts/package-app.sh
```

The generated artifacts are placed under `dist/` and are intentionally ignored by git.

## Run From Source

Run the menu-bar app:

```sh
.build/debug/FocusKeeperApp
```

Run the debug CLI:

```sh
.build/debug/focuskeeper-debug status
.build/debug/focuskeeper-debug on
.build/debug/focuskeeper-debug off
```

The debug CLI defaults to `com.apple.focus.work`.

## How To Use

1. Launch FocusKeeper.
2. Grant Full Disk Access.
3. Open the menu-bar menu and choose `Settings`.
4. Create or select a profile.
5. Choose the Focus mode for that profile.
6. Add watched apps with `Choose Application...`.
7. Configure exit behavior, off delay, and manual Focus change behavior.
8. Keep only the profile you want active enabled, or choose the active profile from the menu.

FocusKeeper watches running applications by bundle identifier. It does not use the active or frontmost application to decide Focus state.

## Uninstall

1. Quit FocusKeeper.
2. Remove `FocusKeeper.app` from `/Applications` or wherever you installed it.
3. Optional: remove the user config and backups:

```sh
rm -rf "$HOME/Library/Application Support/FocusKeeper"
```

4. Optional: remove logs:

```sh
rm -f "$HOME/Library/Logs/FocusKeeper.log"
rm -f "$HOME/Library/Logs/FocusKeeper.launchd.out.log"
rm -f "$HOME/Library/Logs/FocusKeeper.launchd.err.log"
```

5. If Launch at Login was enabled through the LaunchAgent fallback, remove:

```sh
rm -f "$HOME/Library/LaunchAgents/com.focuskeeper.app.plist"
launchctl unload "$HOME/Library/LaunchAgents/com.focuskeeper.app.plist" 2>/dev/null || true
```

## Backups And Logs

Before the first write in each app process session, FocusKeeper creates a backup under:

```text
~/Library/Application Support/FocusKeeper/Backups/
```

Logs are written to:

```text
~/Library/Logs/FocusKeeper.log
```

## Known Limitations

- Experimental backend using private macOS files.
- Tested on macOS 26.5; other versions may differ.
- Requires Full Disk Access.
- The app is not notarized.
- Local builds may be unsigned or ad-hoc signed.
- Launch at Login currently uses a LaunchAgent fallback for this SwiftPM app structure.
- macOS updates may change `Assertions.json` or `ModeConfigurations.json`.
- Duplicate Focus notifications may still happen if macOS reports state changes unexpectedly.
- Recovery may require manually restoring an `Assertions.json` backup.

## Privacy

FocusKeeper is local-only. It does not send data anywhere and does not use any network API.

The app reads local running application bundle identifiers and local macOS Focus configuration files. Diagnostics intentionally avoid dumping full JSON database files and do not read `ModeConfigurationsSecure.json`.

## License

MIT License. See [LICENSE](LICENSE).
