import AppKit
import MacWorkspacesCore

// Command-line entry points (useful for validation and scripting):
//   MacWorkspaces --print-config   Print the AeroSpace config generated from current settings.
//   MacWorkspaces --version
let arguments = CommandLine.arguments.dropFirst()
if arguments.contains("--print-config") {
    print(ConfigGenerator().render(SettingsStore.defaultStore().load()))
    exit(0)
}
if arguments.contains("--version") {
    print(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "dev")
    exit(0)
}

// One instance only: AeroSpace owns the global shortcuts, and a second companion would
// double-handle launch requests.
if let bundleID = Bundle.main.bundleIdentifier {
    let others = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID)
        .filter { $0.processIdentifier != ProcessInfo.processInfo.processIdentifier }
    if !others.isEmpty {
        others.first?.activate()
        exit(0)
    }
}

MainActor.assumeIsolated {
    let app = NSApplication.shared
    let delegate = AppDelegate()
    app.delegate = delegate
    app.setActivationPolicy(.accessory)
    withExtendedLifetime(delegate) { app.run() }
}
