import AppKit
import MacWorkspacesCore

enum TerminalLaunchError: LocalizedError {
    case automationDenied
    case script(String, Int)
    case launchFailed(String)

    var errorDescription: String? {
        switch self {
        case .automationDenied:
            return "mac-workspaces is not allowed to control Terminal. Enable it in System Settings › Privacy & Security › Automation."
        case .script(let message, let code):
            return "Terminal did not open a window (\(code)): \(message)"
        case .launchFailed(let message):
            return "Could not launch Terminal: \(message)"
        }
    }
}

/// Opens a new, independent Apple Terminal window on every call.
///
/// * Terminal running: `do script ""` always creates a new window (activating alone would not).
/// * Terminal not running: launching it shows its startup window, so we use that one instead
///   of also running `do script` (which would produce two windows).
struct AppleTerminalAdapter: TerminalAdapter {
    let displayName = "Terminal"
    let bundleIdentifier = "com.apple.Terminal"

    func openNewWindow() throws {
        if NSRunningApplication.runningApplications(withBundleIdentifier: bundleIdentifier).isEmpty {
            try launchTerminal()
            if waitForWindow(timeout: 1.5) {
                try runScript("tell application \"Terminal\" to activate")
                return
            }
        }
        try runScript("""
        tell application "Terminal"
            do script ""
            activate
        end tell
        """)
    }

    private func launchTerminal() throws {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier) else {
            throw TerminalLaunchError.launchFailed("Terminal.app not found")
        }
        let done = DispatchSemaphore(value: 0)
        var failure: Error?
        let config = NSWorkspace.OpenConfiguration()
        config.activates = true
        NSWorkspace.shared.openApplication(at: url, configuration: config) { _, error in
            failure = error
            done.signal()
        }
        _ = done.wait(timeout: .now() + 5)
        if let failure { throw TerminalLaunchError.launchFailed(failure.localizedDescription) }
    }

    /// Waits for Terminal to report at least one window (its startup window).
    private func waitForWindow(timeout: TimeInterval) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if let count = try? runScriptReturningInt("tell application \"Terminal\" to count windows"), count > 0 {
                return true
            }
            Thread.sleep(forTimeInterval: 0.1)
        }
        return false
    }

    private func runScriptReturningInt(_ source: String) throws -> Int {
        Int(try runScript(source).int32Value)
    }

    @discardableResult
    private func runScript(_ source: String) throws -> NSAppleEventDescriptor {
        // NSAppleScript is main-thread-only; launches run on a background queue.
        var result: Result<NSAppleEventDescriptor, Error> = .failure(TerminalLaunchError.script("not run", 0))
        let work = {
            var error: NSDictionary?
            let script = NSAppleScript(source: source)
            if let descriptor = script?.executeAndReturnError(&error) {
                result = .success(descriptor)
            } else {
                let code = (error?[NSAppleScript.errorNumber] as? Int) ?? 0
                let message = (error?[NSAppleScript.errorMessage] as? String) ?? "unknown error"
                result = .failure(code == -1743 ? TerminalLaunchError.automationDenied : TerminalLaunchError.script(message, code))
            }
        }
        if Thread.isMainThread { work() } else { DispatchQueue.main.sync(execute: work) }
        return try result.get()
    }
}

/// Polls whether a physical key is held. Used to tell auto-repeat from deliberate presses.
enum KeyState {
    static func isDown(_ keyCode: UInt16) -> Bool {
        CGEventSource.keyState(.combinedSessionState, key: CGKeyCode(keyCode))
    }
}
