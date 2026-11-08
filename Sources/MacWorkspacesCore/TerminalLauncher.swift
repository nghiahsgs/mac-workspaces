import Foundation

/// Creates a new window in a specific terminal app. Simply activating the app is not enough:
/// every call must produce a new, independent window.
public protocol TerminalAdapter: Sendable {
    var displayName: String { get }
    var bundleIdentifier: String { get }
    func openNewWindow() throws
}

public struct LaunchResult: Equatable, Sendable {
    public enum Placement: Equatable, Sendable {
        /// The new window appeared in the requested workspace.
        case inTarget
        /// It appeared elsewhere (e.g. the user switched workspace meanwhile) and was moved.
        case corrected(from: String)
        /// AeroSpace did not report a new window before the timeout.
        case notDetected
        /// AeroSpace was unavailable, so placement was not verified.
        case unverified
    }

    public let windowID: Int?
    public let targetWorkspace: String?
    public let placement: Placement
    public let elapsed: TimeInterval
}

/// Orchestrates a terminal launch:
/// 1. remember the workspace that was active when the shortcut was pressed,
/// 2. snapshot existing terminal windows,
/// 3. ask the adapter for a new window,
/// 4. wait for AeroSpace to report it and move it to the remembered workspace if it landed
///    somewhere else, then focus it.
///
/// Launches must be serialized by the caller so window snapshots do not overlap.
public struct TerminalLauncher: Sendable {
    public let aerospace: AeroSpaceControlling
    public let terminal: TerminalAdapter
    public let detectionTimeout: TimeInterval
    public let pollInterval: TimeInterval
    public let sleep: @Sendable (TimeInterval) -> Void
    public let clock: @Sendable () -> Date

    public init(
        aerospace: AeroSpaceControlling,
        terminal: TerminalAdapter,
        detectionTimeout: TimeInterval = 2.5,
        pollInterval: TimeInterval = 0.05,
        sleep: @escaping @Sendable (TimeInterval) -> Void = { Thread.sleep(forTimeInterval: $0) },
        clock: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.aerospace = aerospace
        self.terminal = terminal
        self.detectionTimeout = detectionTimeout
        self.pollInterval = pollInterval
        self.sleep = sleep
        self.clock = clock
    }

    /// The workspace to capture at request time, before any queueing delay.
    public func currentWorkspace() -> String? {
        try? aerospace.focusedWorkspace()
    }

    public func launch(targetWorkspace: String?) throws -> LaunchResult {
        let start = clock()
        let before: Set<Int>? = (try? aerospace.windows(appBundleID: terminal.bundleIdentifier)).map { Set($0.map(\.id)) }

        try terminal.openNewWindow()

        guard let before, let target = targetWorkspace else {
            return LaunchResult(windowID: nil, targetWorkspace: targetWorkspace, placement: .unverified, elapsed: clock().timeIntervalSince(start))
        }

        while clock().timeIntervalSince(start) < detectionTimeout {
            if let windows = try? aerospace.windows(appBundleID: terminal.bundleIdentifier),
               let newWindow = windows.filter({ !before.contains($0.id) }).max(by: { $0.id < $1.id }) {
                var placement = LaunchResult.Placement.inTarget
                if newWindow.workspace != target {
                    try? aerospace.moveWindow(newWindow.id, toWorkspace: target)
                    placement = .corrected(from: newWindow.workspace)
                }
                // Focus only if the user is still looking at the target workspace; never
                // yank them back if they deliberately moved on.
                if (try? aerospace.focusedWorkspace()) == target {
                    try? aerospace.focusWindow(newWindow.id)
                }
                return LaunchResult(windowID: newWindow.id, targetWorkspace: target, placement: placement, elapsed: clock().timeIntervalSince(start))
            }
            sleep(pollInterval)
        }
        return LaunchResult(windowID: nil, targetWorkspace: target, placement: .notDetected, elapsed: clock().timeIntervalSince(start))
    }
}
