import AppKit
import Combine
import MacWorkspacesCore

/// Central state for the menu bar companion.
@MainActor
final class AppModel: ObservableObject {
    // Persisted preferences.
    @Published var settings: Settings { didSet { if settings != oldValue { persist() } } }

    // Live state.
    @Published private(set) var snapshot = WorkspaceSnapshot(focused: nil, occupied: [])
    @Published private(set) var aerospaceReachable = false
    @Published private(set) var aerospaceVersion: String?
    @Published private(set) var cliInstalled = false
    @Published private(set) var automationStatus: PermissionStatus = .unknown("Not checked")
    @Published private(set) var configPlan: ConfigPlan?
    @Published private(set) var configProblem: String?
    @Published private(set) var backups: [URL] = []
    @Published var lastMessage: String?

    var isPaused: Bool { snapshot.mode == ConfigGenerator.pausedMode }
    var issues: [BindingIssue] { BindingValidator.validate(settings) }
    var hasBlockingIssues: Bool { issues.contains { $0.severity == .error } }

    let store = SettingsStore.defaultStore()
    let configManager = ConfigManager()
    let generator = ConfigGenerator()
    let aerospace = AeroSpaceCLI()

    private let terminal = AppleTerminalAdapter()
    private lazy var launcher = TerminalLauncher(aerospace: aerospace, terminal: terminal)
    private var gate: LaunchGate
    private let captureQueue = DispatchQueue(label: "macworkspaces.launch.capture")
    private let launchQueue = DispatchQueue(label: "macworkspaces.launch")
    private let refreshQueue = DispatchQueue(label: "macworkspaces.refresh")
    private var monitor: WorkspaceMonitor?
    private var keyReleaseTimer: Timer?

    init() {
        let loaded = SettingsStore.defaultStore().load()
        settings = loaded
        gate = AppModel.makeGate(for: loaded)
    }

    private static func makeGate(for settings: Settings) -> LaunchGate {
        let key = settings.shortcut(for: .launchTerminal)?.key
        let observable = key.flatMap { KeyNames.virtualKeyCodes[$0] } != nil
        return LaunchGate(observesKeyState: observable)
    }

    func start() {
        refreshStatus()
        monitor = WorkspaceMonitor(aerospace: aerospace) { [weak self] in
            Task { @MainActor in self?.refreshWorkspaces() }
        }
        monitor?.start()
    }

    private func persist() {
        do { try store.save(settings) } catch { lastMessage = "Could not save settings: \(error.localizedDescription)" }
        gate = AppModel.makeGate(for: settings)
        refreshConfigPlan()
    }

    // MARK: Status

    func refreshStatus() {
        cliInstalled = aerospace.executable != nil
        refreshConfigPlan()
        backups = configManager.backups()
        refreshWorkspaces()
        checkAutomation(ask: false)
    }

    func refreshWorkspaces() {
        let aerospace = self.aerospace
        refreshQueue.async {
            let snap = try? aerospace.snapshot()
            let version = snap == nil ? nil : (try? aerospace.version())
            DispatchQueue.main.async {
                if let snap { self.snapshot = snap }
                // AeroSpace (re)appeared: retry the event subscription it may have refused.
                if snap != nil && !self.aerospaceReachable { self.monitor?.resetBackoff() }
                self.aerospaceReachable = snap != nil
                if let version { self.aerospaceVersion = version }
            }
        }
    }

    func refreshConfigPlan() {
        do {
            configPlan = try configManager.plan(proposed: generator.render(settings))
            configProblem = nil
        } catch {
            configPlan = nil
            configProblem = error.localizedDescription
        }
    }

    func checkAutomation(ask: Bool) {
        let bundleID = terminal.bundleIdentifier
        DispatchQueue.global().async {
            // macOS can only answer (or prompt) while the target app is running.
            if ask, NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).isEmpty,
               let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
                let config = NSWorkspace.OpenConfiguration()
                config.activates = false
                NSWorkspace.shared.openApplication(at: url, configuration: config)
                let deadline = Date().addingTimeInterval(5)
                while NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first?.isFinishedLaunching != true,
                      Date() < deadline {
                    Thread.sleep(forTimeInterval: 0.1)
                }
            }
            let status = Automation.status(bundleID: bundleID, ask: ask)
            DispatchQueue.main.async { self.automationStatus = status }
        }
    }

    /// One-line health summary for the menu, or nil when everything works.
    var statusProblem: String? {
        if !cliInstalled && !AeroSpaceApp.isInstalled { return "AeroSpace is not installed" }
        if !aerospaceReachable { return AeroSpaceApp.isRunning ? "AeroSpace is not responding" : "AeroSpace is not running" }
        if let configProblem { return configProblem }
        if automationStatus == .denied { return "Terminal control is not allowed" }
        if !settings.setupCompleted { return "Setup is not finished" }
        return nil
    }

    // MARK: Configuration

    /// Writes the generated config (backing up any existing file) and reloads AeroSpace.
    func applyConfig() {
        guard !hasBlockingIssues else {
            lastMessage = "Fix the shortcut conflicts before applying."
            return
        }
        do {
            let plan = try configManager.plan(proposed: generator.render(settings))
            let backup = try configManager.apply(plan)
            var message = "Configuration written to \(plan.target.path)."
            if let backup { message += " Previous file backed up as \(backup.lastPathComponent)." }
            if aerospaceReachable {
                do { try aerospace.reloadConfig(); message += " AeroSpace reloaded." }
                catch { message += " AeroSpace reported a problem: \(error.localizedDescription) You can restore the backup in Settings › Configuration." }
            }
            lastMessage = message
            settings.setupCompleted = true
        } catch {
            lastMessage = "Could not apply configuration: \(error.localizedDescription)"
        }
        refreshStatus()
    }

    func restore(_ backup: URL) {
        do {
            let target = try configManager.restore(backup)
            var message = "Restored \(backup.lastPathComponent) to \(target.path)."
            if aerospaceReachable {
                do { try aerospace.reloadConfig(); message += " AeroSpace reloaded." }
                catch { message += " AeroSpace reported a problem: \(error.localizedDescription)" }
            }
            lastMessage = message
        } catch {
            lastMessage = "Could not restore: \(error.localizedDescription)"
        }
        refreshStatus()
    }

    // MARK: Actions

    func switchWorkspace(_ name: String) {
        run { try $0.switchWorkspace(name) }
    }

    func perform(_ action: Action) {
        switch action {
        case .launchTerminal: requestTerminalLaunch(fromMenu: true)
        case .togglePause: togglePause()
        default:
            guard let args = action.cliArguments else { return }
            run { _ = try $0.run(args) }
        }
    }

    func togglePause() {
        let target = isPaused ? "main" : ConfigGenerator.pausedMode
        run { try $0.setMode(target) } onError: { [weak self] _ in
            self?.lastMessage = "Pause needs the mac-workspaces configuration applied (it defines the paused mode)."
        }
    }

    private func run(_ body: @escaping (AeroSpaceCLI) throws -> Void, onError: ((Error) -> Void)? = nil) {
        let aerospace = self.aerospace
        refreshQueue.async {
            do {
                try body(aerospace)
                DispatchQueue.main.async { self.refreshWorkspaces() }
            } catch {
                DispatchQueue.main.async {
                    if let onError { onError(error) } else { self.lastMessage = error.localizedDescription }
                    self.refreshWorkspaces()
                }
            }
        }
    }

    // MARK: Terminal launch

    /// Handles `macworkspaces://launch-terminal` (sent by the AeroSpace binding) and the menu item.
    func requestTerminalLaunch(fromMenu: Bool = false, pressedOnWorkspace: String? = nil) {
        // Menu clicks cannot auto-repeat; only filter keyboard-originated requests.
        if !fromMenu {
            guard gate.shouldAccept() else { return }
            watchLaunchKeyRelease()
        }
        let launcher = self.launcher
        let launchQueue = self.launchQueue
        // Capture the active workspace immediately (cheap), then queue the slower launch so
        // rapid presses are handled one at a time and in order.
        captureQueue.async {
            let target = pressedOnWorkspace ?? launcher.currentWorkspace()
            launchQueue.async {
                do {
                    let result = try launcher.launch(targetWorkspace: target)
                    if result.placement == .notDetected {
                        DispatchQueue.main.async {
                            self.lastMessage = "Opened a Terminal window, but AeroSpace did not report it within \(Int(launcher.detectionTimeout)) s."
                        }
                    }
                } catch {
                    DispatchQueue.main.async {
                        self.lastMessage = error.localizedDescription
                        if case TerminalLaunchError.automationDenied = error { self.automationStatus = .denied }
                    }
                }
                DispatchQueue.main.async { self.refreshWorkspaces() }
            }
        }
    }

    private func watchLaunchKeyRelease() {
        guard gate.observesKeyState,
              let key = settings.shortcut(for: .launchTerminal)?.key,
              let code = KeyNames.virtualKeyCodes[key] else { return }
        keyReleaseTimer?.invalidate()
        let gate = self.gate
        keyReleaseTimer = Timer.scheduledTimer(withTimeInterval: 0.015, repeats: true) { timer in
            if !KeyState.isDown(code) {
                gate.keyReleased()
                timer.invalidate()
            }
        }
    }
}

/// Keeps the workspace indicator current.
///
/// Uses `aerospace subscribe` (event stream) when available, plus a slow poll that also
/// catches window closes and recovers after AeroSpace restarts.
final class WorkspaceMonitor {
    private let aerospace: AeroSpaceCLI
    private let onChange: () -> Void
    private var process: Process?
    private var pollTimer: Timer?
    /// Older AeroSpace versions lack `subscribe`; stop retrying after repeated quick exits
    /// and rely on polling alone.
    private var quickExits = 0
    private var startedAt = Date()

    init(aerospace: AeroSpaceCLI, onChange: @escaping () -> Void) {
        self.aerospace = aerospace
        self.onChange = onChange
    }

    func start() {
        pollTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            self?.onChange()
            if self?.process?.isRunning != true { self?.startSubscription() }
        }
        startSubscription()
    }

    private func startSubscription() {
        guard let executable = aerospace.executable, process?.isRunning != true, quickExits < 3 else { return }
        if process != nil, Date().timeIntervalSince(startedAt) < 5 { quickExits += 1 } else if process != nil { quickExits = 0 }
        startedAt = Date()
        let p = Process()
        p.executableURL = executable
        p.arguments = ["subscribe", "focused-workspace-changed", "focus-changed", "mode-changed", "window-detected"]
        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = FileHandle.nullDevice
        pipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            if handle.availableData.isEmpty { handle.readabilityHandler = nil; return }
            DispatchQueue.main.async { self?.scheduleCoalescedChange() }
        }
        do { try p.run(); process = p } catch { process = nil }
    }

    private var pendingChange: DispatchWorkItem?

    func resetBackoff() {
        quickExits = 0
        if process?.isRunning != true { process = nil; startSubscription() }
    }

    /// Focus events can arrive in bursts; refresh at most once per 100 ms burst.
    private func scheduleCoalescedChange() {
        guard pendingChange == nil else { return }
        let work = DispatchWorkItem { [weak self] in
            self?.pendingChange = nil
            self?.onChange()
        }
        pendingChange = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1, execute: work)
    }

    deinit {
        pollTimer?.invalidate()
        process?.terminate()
    }
}
