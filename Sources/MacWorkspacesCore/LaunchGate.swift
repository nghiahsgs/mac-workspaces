import Foundation

/// Decides whether a terminal-launch request is a deliberate press or keyboard auto-repeat.
///
/// AeroSpace fires a binding for every key-down event, including auto-repeat while the key
/// is held. The companion receives each as a launch request. Two strategies:
///
/// * **Key-state (preferred):** after accepting a request the gate disarms until the launch
///   key is observed released (the app polls the physical key state and calls
///   `keyReleased()`). Requests that arrive while the key is still held are auto-repeat.
/// * **Timing fallback:** when the key cannot be observed, requests that follow the previous
///   request within `repeatWindow` are treated as repeat (a sliding window, so a continuous
///   stream of repeats keeps being suppressed).
public final class LaunchGate: @unchecked Sendable {
    public let minimumInterval: TimeInterval
    public let repeatWindow: TimeInterval
    public let disarmTimeout: TimeInterval
    public let observesKeyState: Bool

    private let lock = NSLock()
    private var armed = true
    private var lastAccepted: Date?
    private var lastRequest: Date?

    /// - Parameters:
    ///   - observesKeyState: true when the app can poll the launch key and will call `keyReleased()`.
    ///   - minimumInterval: hard floor between accepted launches (guards double delivery).
    ///   - repeatWindow: timing-fallback window; typical macOS repeat intervals are 15–120 ms.
    ///   - disarmTimeout: re-arm automatically if no release is observed (e.g. a missed key-up).
    public init(observesKeyState: Bool, minimumInterval: TimeInterval = 0.05, repeatWindow: TimeInterval = 0.15, disarmTimeout: TimeInterval = 5) {
        self.observesKeyState = observesKeyState
        self.minimumInterval = minimumInterval
        self.repeatWindow = repeatWindow
        self.disarmTimeout = disarmTimeout
    }

    /// Returns true if a terminal window should be created for this request.
    public func shouldAccept(at now: Date = Date()) -> Bool {
        lock.lock(); defer { lock.unlock() }
        defer { lastRequest = now }

        if let last = lastAccepted, now.timeIntervalSince(last) < minimumInterval { return false }

        if observesKeyState {
            if !armed, let last = lastAccepted, now.timeIntervalSince(last) > disarmTimeout { armed = true }
            guard armed else { return false }
            armed = false
        } else if let previous = lastRequest, now.timeIntervalSince(previous) < repeatWindow {
            return false
        }
        lastAccepted = now
        return true
    }

    /// Whether the gate is waiting for the launch key to be released.
    public var isWaitingForRelease: Bool {
        lock.lock(); defer { lock.unlock() }
        return observesKeyState && !armed
    }

    /// Call when the launch key is observed released after an accepted request.
    public func keyReleased() {
        lock.lock(); armed = true; lock.unlock()
    }
}
