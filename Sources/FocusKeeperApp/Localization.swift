import Foundation

enum AppLanguage: String, Codable {
    case english
    case russian
}

enum AppLanguagePreference: String, Codable, CaseIterable, Identifiable {
    case system
    case english
    case russian

    var id: String { rawValue }

    var effectiveLanguage: AppLanguage {
        switch self {
        case .english:
            return .english
        case .russian:
            return .russian
        case .system:
            let preferredLanguage = Locale.preferredLanguages.first?.lowercased() ?? ""
            return preferredLanguage.hasPrefix("ru") ? .russian : .english
        }
    }

    func title(in language: AppLanguage) -> String {
        switch (self, language) {
        case (.system, .russian):
            return "Как в системе"
        case (.system, .english):
            return "System"
        case (.english, .russian):
            return "English"
        case (.english, .english):
            return "English"
        case (.russian, .russian):
            return "Русский"
        case (.russian, .english):
            return "Russian"
        }
    }
}

struct AppStrings {
    let language: AppLanguage

    init(_ language: AppLanguage) {
        self.language = language
    }

    var settingsTitle: String { text("Settings", "Настройки") }
    var headerSubtitle: String {
        text(
            "Automatically keeps the selected Focus mode enabled while chosen apps are running.",
            "Автоматически удерживает выбранный Focus, пока работают нужные приложения."
        )
    }
    var refresh: String { text("Refresh", "Обновить") }
    var fullDiskTitle: String { text("Full Disk Access Required", "Нужен Full Disk Access") }
    var fullDiskBody: String {
        text(
            "FocusKeeper needs Full Disk Access to manage macOS Focus directly.",
            "FocusKeeper needs Full Disk Access to manage macOS Focus directly."
        )
    }
    var fullDiskPath: String {
        text(
            "System Settings → Privacy & Security → Full Disk Access → enable FocusKeeper",
            "System Settings → Privacy & Security → Full Disk Access → enable FocusKeeper"
        )
    }
    var openFullDiskSettings: String { text("Open Full Disk Access Settings", "Открыть настройки доступа") }
    var checkAgain: String { text("Check Again", "Проверить снова") }
    var overviewAccess: String { text("Access", "Доступ") }
    var overviewAccessNeeded: String { text("Needed", "Нужен") }
    var overviewAccessReady: String { text("Ready", "Готов") }
    var overviewApps: String { text("Apps", "Приложений") }
    var overviewLaunch: String { text("Login", "Автозапуск") }
    var onShort: String { text("On", "Вкл") }
    var offShort: String { text("Off", "Выкл") }
    var unknownShort: String { text("Unknown", "Неизвестно") }
    var focusEnabled: String { text("Focus On", "Focus включен") }
    var focusDisabled: String { text("Focus Off", "Focus выключен") }
    var focusUnknown: String { text("Unknown", "неизвестно") }
    var none: String { text("None", "нет") }
    var yes: String { text("Yes", "да") }
    var no: String { text("No", "нет") }

    var languageTitle: String { text("Language", "Язык") }
    var languageSubtitle: String {
        text(
            "Use the system language automatically, or choose Russian or English manually.",
            "Используйте язык системы автоматически или выберите русский/английский вручную."
        )
    }
    var languagePickerLabel: String { text("Interface language", "Язык интерфейса") }

    var focusModeTitle: String { text("Focus Mode", "Режим фокусирования") }
    var focusModeSubtitle: String {
        text(
            "Choose the macOS Focus mode controlled by FocusKeeper.",
            "Выберите режим macOS Focus, которым будет управлять FocusKeeper."
        )
    }
    var focusExitBehaviorTitle: String { text("When watched apps quit", "Когда приложения закрыты") }
    var focusExitBehaviorSubtitle: String {
        text(
            "Choose whether FocusKeeper turns Focus off or restores the mode that was active before it intervened.",
            "Выберите, выключать Focus или возвращать режим, который был активен до вмешательства FocusKeeper."
        )
    }
    var focusExitBehaviorPickerLabel: String { text("After apps quit", "После закрытия") }
    var focusExitTurnOff: String { text("Turn off Focus", "Выключать Focus") }
    var focusExitRestorePrevious: String { text("Restore previous", "Возвращать предыдущий") }
    var focusExitTurnOffHelp: String {
        text(
            "When no watched apps are running, FocusKeeper clears active Focus assertions.",
            "Когда отслеживаемые приложения не запущены, FocusKeeper очищает активные записи Focus."
        )
    }
    var focusExitRestoreHelp: String {
        text(
            "If another Focus mode was active before FocusKeeper turned this one on, it will be restored.",
            "Если до автоматического включения был активен другой режим, FocusKeeper вернет его обратно."
        )
    }
    var profilesTitle: String { text("Profiles", "Профили") }
    var profilesSubtitle: String {
        text(
            "Profiles are checked from top to bottom. The first enabled matching profile wins.",
            "Профили проверяются сверху вниз. Первый включенный подходящий профиль имеет приоритет."
        )
    }
    var addProfile: String { text("Add Profile", "Добавить профиль") }
    var deleteProfile: String { text("Delete Profile", "Удалить профиль") }
    var moveUp: String { text("Move Up", "Выше") }
    var moveDown: String { text("Move Down", "Ниже") }
    var profileName: String { text("Profile name", "Название профиля") }
    var profileEnabled: String { text("Active profile", "Активный профиль") }
    var activateProfile: String { text("Activate Profile", "Активировать профиль") }
    var chooseActiveProfile: String { text("Choose Active Profile", "Выбрать активный профиль") }
    var profilePriorityHelp: String {
        text(
            "Only one profile can be active. Use Move Up/Down to keep your list organized.",
            "Активным может быть только один профиль. Используйте Выше/Ниже для порядка в списке."
        )
    }
    var automationPaused: String { text("Automation is paused", "Автоматизация приостановлена") }
    var automationRunning: String { text("Automation is running", "Автоматизация работает") }
    var offDelayTitle: String { text("Delay before turning off", "Задержка перед отключением") }
    var offDelayCustom: String { text("Custom seconds", "Свои секунды") }
    var manualFocusChanges: String { text("Manual Focus changes", "Ручное изменение фокусирования") }
    var manualFocusChangesSubtitle: String {
        text(
            "Choose what happens if Focus is changed while this profile is active.",
            "Выберите, что делать, если Focus изменили вручную во время работы профиля."
        )
    }
    var respectManualChanges: String { text("Respect manual changes", "Уважать ручные изменения") }
    var forceSelectedFocus: String { text("Force selected Focus", "Принудительно возвращать выбранный режим") }
    var respectManualChangesHelp: String {
        text(
            "FocusKeeper will not fight the user if Focus is changed manually while this profile is active.",
            "FocusKeeper не будет спорить с пользователем, если Focus изменили вручную, пока профиль активен."
        )
    }
    var forceSelectedFocusHelp: String {
        text(
            "FocusKeeper will return this profile's Focus mode during reconciliation while watched apps are running.",
            "FocusKeeper будет возвращать режим этого профиля при синхронизации, пока приложения запущены."
        )
    }
    var modePickerLabel: String { text("Mode", "Режим") }
    var refreshModes: String { text("Refresh modes", "Обновить режимы") }
    var modeIdentifier: String { text("Identifier", "Идентификатор") }
    var noModesFallback: String {
        text(
            "No Focus modes were discovered. Using verified fallback: Work (com.apple.focus.work).",
            "Режимы не найдены. Используется проверенный fallback: Работа (com.apple.focus.work)."
        )
    }

    var launchTitle: String { text("Startup", "Запуск") }
    var launchSubtitle: String {
        text(
            "FocusKeeper starts silently and immediately syncs state based on running apps.",
            "FocusKeeper запускается тихо и сразу синхронизирует состояние по запущенным приложениям."
        )
    }
    var launchAtLogin: String { text("Launch FocusKeeper at Login", "Запускать FocusKeeper при входе") }
    var launchFallbackDescription: String {
        text(
            "Launch at Login uses a user LaunchAgent fallback because this SwiftPM executable is not currently packaged as a signed app bundle for SMAppService.",
            "Автозапуск использует LaunchAgent, потому что текущая сборка SwiftPM еще не упакована как подписанное .app для SMAppService."
        )
    }

    var watchedAppsTitle: String { text("Watched Apps", "Отслеживаемые приложения") }
    var watchedAppsSubtitle: String {
        text(
            "Choose apps from Applications. Focus turns on while at least one selected app is running.",
            "Выберите приложения из Applications. Focus включается, пока запущено хотя бы одно выбранное приложение."
        )
    }
    var chooseApplication: String { text("Choose Application…", "Выбрать приложение…") }
    var noWatchedAppsTitle: String { text("No watched apps", "Нет выбранных приложений") }
    var noWatchedAppsMessage: String {
        text(
            "Add an app from Applications. FocusKeeper stores its bundle ID and watches whether it is running.",
            "Добавьте приложение из Applications. FocusKeeper сохранит bundle ID и будет отслеживать, запущено ли оно."
        )
    }
    var remove: String { text("Remove", "Удалить") }

    var addManuallyTitle: String { text("Manual Bundle ID", "Bundle ID вручную") }
    var addManuallySubtitle: String { text("Advanced fallback if the app cannot be selected from Finder.", "Дополнительный вариант, если приложение не удалось выбрать через Finder.") }
    var add: String { text("Add", "Добавить") }
    var noSelectedApps: String { text("No apps selected yet.", "Пока не выбрано ни одного приложения.") }
    var selectedBundleIDs: String { text("Selected bundle IDs", "Выбранные bundle ID") }
    var selected: String { text("Selected", "Выбран") }
    var select: String { text("Select", "Выбрать") }
    var symbol: String { text("Symbol", "Символ") }

    var menuCurrentStatus: String { text("Current status", "Текущий статус") }
    var menuActiveProfile: String { text("Active profile", "Активный профиль") }
    var menuNoActiveProfile: String { text("No active profile", "Нет активного профиля") }
    var menuPendingOff: String { text("Turning off in", "Отключение через") }
    var menuCancelPendingOff: String { text("Cancel pending off", "Отменить отложенное отключение") }
    var menuPause: String { text("Pause FocusKeeper", "Приостановить FocusKeeper") }
    var menuPause15: String { text("Pause for 15 minutes", "Приостановить на 15 минут") }
    var menuPauseHour: String { text("Pause for 1 hour", "Приостановить на 1 час") }
    var menuPauseTomorrow: String { text("Pause until tomorrow", "Приостановить до завтра") }
    var menuPauseIndefinitely: String { text("Pause indefinitely", "Приостановить бессрочно") }
    var menuResume: String { text("Resume FocusKeeper", "Возобновить FocusKeeper") }
    var menuPaused: String { text("Paused", "Приостановлено") }
    var menuDiagnostics: String { text("Diagnostics", "Диагностика") }
    var menuWatchedRunning: String { text("Watched apps running", "Запущено отслеживаемых") }
    var menuDesired: String { text("Desired", "Нужно") }
    var menuDesiredOn: String { text("Turn On", "Включить") }
    var menuDesiredOff: String { text("Turn Off", "Выключить") }
    var menuActual: String { text("Actual", "Фактически") }
    var menuPermissionError: String { text("Permission/Error", "Ошибка/доступ") }
    var menuError: String { text("Error", "Ошибка") }
    var menuNoError: String { text("None", "нет") }
    var menuSyncNow: String { text("Sync Now", "Синхронизировать сейчас") }
    var menuCheckPermissions: String { text("Check Permissions", "Проверить доступ") }
    var menuSettings: String { text("Settings", "Настройки") }
    var menuQuit: String { text("Quit", "Выйти") }
    var menuTurnOffNow: String { text("Turn Focus Off Now", "Выключить Focus сейчас") }
    var menuTurnOnNow: String { text("Turn Focus On Now", "Включить Focus сейчас") }
    var permissionsOK: String { text("Access: Full Disk Access OK", "Доступ: Full Disk Access есть") }
    var permissionsNeeded: String { text("Access: Full Disk Access Needed", "Доступ: нужен Full Disk Access") }
    var permissionsUnknown: String { text("Access: Unknown", "Доступ: неизвестно") }
    var alertUpdateFailed: String { text("FocusKeeper could not update Focus", "FocusKeeper не смог изменить Focus") }
    var alertOK: String { text("OK", "ОК") }
    var deleteProfileTitle: String { text("Delete profile?", "Удалить профиль?") }
    var deleteProfileMessage: String {
        text(
            "This removes the profile and its watched app list. This cannot be undone.",
            "Профиль и список его приложений будут удалены. Это действие нельзя отменить."
        )
    }
    var delete: String { text("Delete", "Удалить") }
    var cancel: String { text("Cancel", "Отмена") }

    var diagnosticsTitle: String { text("Diagnostics", "Диагностика") }
    var refreshDiagnostics: String { text("Refresh Diagnostics", "Обновить диагностику") }
    var openLogFile: String { text("Open Log File", "Открыть лог") }
    var openBackupFolder: String { text("Open Backup Folder", "Открыть папку backups") }
    var copyDiagnostics: String { text("Copy Diagnostics to Clipboard", "Скопировать диагностику") }
    var appVersion: String { text("App version", "Версия приложения") }
    var macOSVersion: String { text("macOS version", "Версия macOS") }
    var fullDiskAccessStatus: String { text("Full Disk Access", "Full Disk Access") }
    var assertionsPath: String { text("Assertions.json path", "Путь Assertions.json") }
    var assertionsReadable: String { text("Assertions.json readable", "Assertions.json читается") }
    var assertionsWritable: String { text("Assertions.json writable", "Assertions.json доступен для записи") }
    var modesPath: String { text("ModeConfigurations.json path", "Путь ModeConfigurations.json") }
    var modesReadable: String { text("ModeConfigurations readable", "ModeConfigurations читается") }
    var discoveredModes: String { text("Discovered Focus modes", "Найдено режимов Focus") }
    var selectedProfile: String { text("Selected profile", "Выбранный профиль") }
    var selectedFocusMode: String { text("Selected Focus mode", "Выбранный режим Focus") }
    var activeProfile: String { text("Active profile", "Активный профиль") }
    var runningWatchedApps: String { text("Running watched apps", "Запущенные отслеживаемые приложения") }
    var desiredFocusState: String { text("Desired Focus state", "Желаемое состояние Focus") }
    var pendingOffStatus: String { text("Pending off timer", "Таймер отложенного отключения") }
    var pauseStatus: String { text("Pause status", "Состояние паузы") }
    var lastBackendAction: String { text("Last backend action", "Последнее действие backend") }
    var lastBackendActionTime: String { text("Last backend action time", "Время последнего действия backend") }
    var lastSleepWakeSync: String { text("Last sleep/wake sync", "Последняя синхронизация sleep/wake") }
    var lastError: String { text("Last error", "Последняя ошибка") }
    var logFilePath: String { text("Log file path", "Путь к логу") }
    var backupFolderPath: String { text("Backup folder path", "Папка backups") }

    private func text(_ english: String, _ russian: String) -> String {
        language == .russian ? russian : english
    }

    func focusModeName(_ mode: FocusMode) -> String {
        switch mode.modeIdentifier {
        case "com.apple.focus.work":
            return text("Work", "Работа")
        case "com.apple.focus.gaming":
            return text("Gaming", "Видеоигры")
        case "com.apple.sleep.sleep-mode":
            return text("Sleep", "Сон")
        case "com.apple.donotdisturb.mode.default":
            return text("Do Not Disturb", "Не беспокоить")
        case "com.apple.focus.reduce-interruptions":
            return text("Reduce Interruptions", "Меньше уведомлений")
        case "com.apple.focus.personal":
            return text("Personal", "Личное")
        case "com.apple.focus.fitness":
            return text("Fitness", "Тренировка")
        case "com.apple.focus.mindfulness":
            return text("Mindfulness", "Осознанность")
        case "com.apple.focus.reading":
            return text("Reading", "Чтение")
        case "com.apple.focus.driving":
            return text("Driving", "За рулем")
        default:
            return mode.name
        }
    }

    func focusExitBehaviorTitle(_ behavior: FocusExitBehavior) -> String {
        switch behavior {
        case .turnOff:
            return focusExitTurnOff
        case .restorePrevious:
            return focusExitRestorePrevious
        }
    }

    func focusExitBehaviorHelp(_ behavior: FocusExitBehavior) -> String {
        switch behavior {
        case .turnOff:
            return focusExitTurnOffHelp
        case .restorePrevious:
            return focusExitRestoreHelp
        }
    }

    func offDelayTitle(_ delay: OffDelay) -> String {
        switch delay {
        case .immediate:
            return text("Immediately", "Сразу")
        case .seconds(30):
            return text("30 seconds", "30 секунд")
        case .seconds(60):
            return text("1 minute", "1 минута")
        case .seconds(300):
            return text("5 minutes", "5 минут")
        case .seconds(900):
            return text("15 minutes", "15 минут")
        case .seconds(let seconds):
            return text("\(seconds) seconds", "\(seconds) сек")
        }
    }

    func manualChangeBehaviorTitle(_ behavior: ManualChangeBehavior) -> String {
        switch behavior {
        case .respectManualChanges:
            return respectManualChanges
        case .forceSelectedFocus:
            return forceSelectedFocus
        }
    }

    func manualChangeBehaviorHelp(_ behavior: ManualChangeBehavior) -> String {
        switch behavior {
        case .respectManualChanges:
            return respectManualChangesHelp
        case .forceSelectedFocus:
            return forceSelectedFocusHelp
        }
    }

    func durationUntil(_ date: Date) -> String {
        let remaining = max(0, Int(date.timeIntervalSinceNow.rounded()))
        let minutes = remaining / 60
        let seconds = remaining % 60
        if language == .russian {
            if minutes > 0 {
                return "\(minutes) мин \(seconds) сек"
            }
            return "\(seconds) сек"
        }

        if minutes > 0 {
            return "\(minutes)m \(seconds)s"
        }
        return "\(seconds)s"
    }
}
