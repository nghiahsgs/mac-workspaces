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
if arguments.contains("--apply-config") {
    // Scripted setup. Same rule as the app: never silently replace a config the user wrote
    // or edited. Those need the reviewed flow in Setup (or --force after reading the diff).
    let settings = SettingsStore.defaultStore().load()
    let errors = BindingValidator.errors(in: settings)
    guard errors.isEmpty else {
        errors.forEach { FileHandle.standardError.write(Data("error: \($0)\n".utf8)) }
        exit(1)
    }
    do {
        let manager = ConfigManager()
        let plan = try manager.plan(proposed: ConfigGenerator().render(settings))
        if plan.requiresReview && !arguments.contains("--force") {
            print(LineDiff.render(plan.currentContents, plan.proposedContents))
            FileHandle.standardError.write(Data("\n\(plan.target.path) was written or edited by hand. Review the diff above, then rerun with --force (a backup is made first) or use Setup.\n".utf8))
            exit(2)
        }
        if let backup = try manager.apply(plan) { print("Backed up previous config to \(backup.path)") }
        print("Wrote \(plan.target.path)")
        if let cli = AeroSpaceCLI().executable, (try? AeroSpaceCLI(executable: cli).reloadConfig()) != nil {
            print("AeroSpace reloaded")
        }
        exit(0)
    } catch {
        FileHandle.standardError.write(Data("error: \(error.localizedDescription)\n".utf8))
        exit(1)
    }
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
