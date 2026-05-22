# Troubleshooting

## Permission Denied

Symptom:

```text
FocusKeeper needs Full Disk Access.
```

Fix:

1. Open `System Settings`.
2. Go to `Privacy & Security`.
3. Open `Full Disk Access`.
4. Enable FocusKeeper.
5. Quit and restart FocusKeeper.
6. Use `Check Permissions` from the FocusKeeper menu.

FocusKeeper needs access to:

```text
~/Library/DoNotDisturb/DB/Assertions.json
~/Library/DoNotDisturb/DB/ModeConfigurations.json
```

## Focus Does Not Enable

Check:

1. FocusKeeper has Full Disk Access.
2. FocusKeeper is not paused.
3. The expected profile is enabled.
4. At least one watched app from that profile is running.
5. The selected Focus mode exists in Settings.
6. If several profiles match, the intended profile is higher in the profile list.
7. `Actual state` in the menu is not `Permission/Error`.
8. `~/Library/Logs/FocusKeeper.log` does not show JSON or permission errors.

You can force a reconciliation from the menu:

```text
Sync Now
```

The backend skips rewriting `Assertions.json` if the selected Focus mode is already active.

## Focus Does Not Disable

Check:

1. No watched apps for the active profile are running.
2. The profile does not have a pending off delay.
3. FocusKeeper is not paused.
4. The watched app did not leave a helper app running with the same bundle identifier.
5. Use `Sync Now` from the menu.
6. Check `~/Library/Logs/FocusKeeper.log`.

The backend skips rewriting `Assertions.json` if `storeAssertionRecords` is already empty.

## App Is Paused

When FocusKeeper is paused, automation does not enable, disable, or restore Focus. This does not turn current Focus off.

Fix:

1. Open the FocusKeeper menu.
2. Choose `Resume FocusKeeper`.
3. Use `Sync Now` if you want immediate reconciliation.

Timed pauses resume automatically after expiration. Indefinite pause persists across app restart.

## Wrong Profile Activates

Profiles are evaluated from top to bottom.

Fix:

1. Open `Settings`.
2. Move the intended profile higher with `Move Up`.
3. Disable profiles that should not currently participate.
4. Confirm watched apps are stored by bundle ID, not display name.

## Manual Focus Changes Are Being Overridden

Open the profile in Settings and check `Manual Focus changes`.

- `Respect manual changes` lets the user manually switch Focus while watched apps keep running.
- `Force selected Focus` restores the profile Focus during reconciliation.

## Copy Diagnostics

Use:

```text
FocusKeeper menu -> Diagnostics -> Copy Diagnostics to Clipboard
```

Paste that report into ChatGPT/Codex for debugging. It includes technical status, paths, active profile, watched bundle IDs, last backend action, and last error. It does not dump full JSON files.

## Open Logs And Backups

The Diagnostics window has buttons for:

```text
Open Log File
Open Backup Folder
Open Full Disk Access Settings
```

## Duplicate Notifications

FocusKeeper has protections against repeated enable/disable loops:

- launch/quit events are debounced by 1.5 seconds;
- only the final desired state is applied after event bursts;
- the watcher keeps `lastAppliedDesiredState` in memory;
- the backend checks the current status before writing;
- existing active selected Focus mode records are not rewritten.

If duplicate notifications still happen:

1. Open Settings.
2. Confirm you are watching only the intended bundle IDs.
3. Check for helper processes that repeatedly launch and quit.
4. Inspect `~/Library/Logs/FocusKeeper.log` for repeated launch/quit events.

## Restore Assertions.json From Backup

Backups are stored in:

```text
~/Library/Application Support/FocusKeeper/Backups/
```

To restore:

1. Quit FocusKeeper.
2. Choose a backup file, usually the newest known-good `Assertions-*.json`.
3. Copy it over:

```sh
cp "$HOME/Library/Application Support/FocusKeeper/Backups/Assertions-YYYYMMDD-HHMMSS.json" \
  "$HOME/Library/DoNotDisturb/DB/Assertions.json"
```

4. Restart only the notification agents needed for the state you are recovering:

```sh
killall donotdisturbd 2>/dev/null || true
killall NotificationCenter 2>/dev/null || true
```

If recovering to an off state, these may also help:

```sh
killall usernotificationsd 2>/dev/null || true
killall usernoted 2>/dev/null || true
```

Do not kill `ControlCenter`.
