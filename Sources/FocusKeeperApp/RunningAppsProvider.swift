import AppKit

struct RunningAppInfo: Identifiable, Equatable {
    var id: String { bundleIdentifier }

    let name: String
    let bundleIdentifier: String
}

@MainActor
final class RunningAppsProvider: ObservableObject {
    @Published private(set) var runningApps: [RunningAppInfo] = []

    init() {
        refresh()
    }

    func refresh() {
        var appsByBundleIdentifier: [String: RunningAppInfo] = [:]

        for app in NSWorkspace.shared.runningApplications {
            guard
                let bundleIdentifier = app.bundleIdentifier,
                !bundleIdentifier.isEmpty,
                isUserFacing(app)
            else {
                continue
            }

            let name = app.localizedName ?? bundleIdentifier
            appsByBundleIdentifier[bundleIdentifier] = RunningAppInfo(
                name: name,
                bundleIdentifier: bundleIdentifier
            )
        }

        runningApps = appsByBundleIdentifier.values.sorted {
            $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }
    }

    private func isUserFacing(_ app: NSRunningApplication) -> Bool {
        app.activationPolicy == .regular || app.activationPolicy == .accessory
    }
}
