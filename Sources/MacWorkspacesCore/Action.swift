import Foundation

public enum Direction: String, Codable, CaseIterable, Sendable {
    case left, down, up, right
}

/// Every action the product can bind to a shortcut.
public enum Action: Hashable, Codable, Sendable, CustomStringConvertible {
    case launchTerminal
    case focus(Direction)
    case move(Direction)
    case switchWorkspace(Int)
    case moveToWorkspace(Int)
    case shrink
    case grow
    case toggleOrientation
    case toggleFloating
    case focusNextMonitor
    case moveToNextMonitor
    case resetLayout
    case togglePause

    public static let workspaceNumbers = Array(1...9)

    /// All actions, in the order they appear in settings and the shortcut reference.
    public static var allCases: [Action] {
        var all: [Action] = [.launchTerminal]
        all += Direction.allCases.map(Action.focus)
        all += Direction.allCases.map(Action.move)
        all += [.shrink, .grow, .toggleOrientation, .toggleFloating]
        all += workspaceNumbers.map(Action.switchWorkspace)
        all += workspaceNumbers.map(Action.moveToWorkspace)
        all += [.focusNextMonitor, .moveToNextMonitor, .resetLayout, .togglePause]
        return all
    }

    /// Stable identifier used as the settings.json key.
    public var id: String {
        switch self {
        case .launchTerminal: return "launch-terminal"
        case .focus(let d): return "focus-\(d.rawValue)"
        case .move(let d): return "move-\(d.rawValue)"
        case .switchWorkspace(let n): return "workspace-\(n)"
        case .moveToWorkspace(let n): return "move-to-workspace-\(n)"
        case .shrink: return "shrink"
        case .grow: return "grow"
        case .toggleOrientation: return "toggle-orientation"
        case .toggleFloating: return "toggle-floating"
        case .focusNextMonitor: return "focus-next-monitor"
        case .moveToNextMonitor: return "move-to-next-monitor"
        case .resetLayout: return "reset-layout"
        case .togglePause: return "toggle-pause"
        }
    }

    public init?(id: String) {
        guard let match = Action.allCases.first(where: { $0.id == id }) else { return nil }
        self = match
    }

    public var description: String { id }

    public var title: String {
        switch self {
        case .launchTerminal: return "Open a new terminal window"
        case .focus(let d): return "Focus \(d.rawValue)"
        case .move(let d): return "Move window \(d.rawValue)"
        case .switchWorkspace(let n): return "Switch to workspace \(n)"
        case .moveToWorkspace(let n): return "Move window to workspace \(n)"
        case .shrink: return "Shrink focused window"
        case .grow: return "Grow focused window"
        case .toggleOrientation: return "Toggle horizontal / vertical tiling"
        case .toggleFloating: return "Toggle floating / tiling"
        case .focusNextMonitor: return "Focus next monitor"
        case .moveToNextMonitor: return "Move window to next monitor"
        case .resetLayout: return "Reset workspace layout"
        case .togglePause: return "Pause / resume shortcuts"
        }
    }

    public var group: String {
        switch self {
        case .launchTerminal: return "Terminal"
        case .focus, .move, .shrink, .grow, .toggleOrientation, .toggleFloating, .resetLayout: return "Windows"
        case .switchWorkspace, .moveToWorkspace: return "Workspaces"
        case .focusNextMonitor, .moveToNextMonitor: return "Monitors"
        case .togglePause: return "Companion"
        }
    }

    /// The PRD's proposed default shortcut, or nil when the action is menu-only by default.
    public var defaultShortcut: Shortcut? {
        switch self {
        case .launchTerminal: return Shortcut([.cmd], "enter")
        case .focus(let d): return Shortcut([.alt], Action.vimKey(d))
        case .move(let d): return Shortcut([.alt, .shift], Action.vimKey(d))
        case .switchWorkspace(let n): return Shortcut([.alt], String(n))
        case .moveToWorkspace(let n): return Shortcut([.alt, .shift], String(n))
        case .shrink: return Shortcut([.alt], "minus")
        case .grow: return Shortcut([.alt], "equal")
        case .toggleOrientation: return Shortcut([.alt], "slash")
        case .toggleFloating, .focusNextMonitor, .moveToNextMonitor, .resetLayout, .togglePause:
            return nil
        }
    }

    static func vimKey(_ d: Direction) -> String {
        switch d {
        case .left: return "h"
        case .down: return "j"
        case .up: return "k"
        case .right: return "l"
        }
    }

    /// The AeroSpace command(s) that implement this action inside the `main` binding mode.
    /// `launchCommand` is the shell command the companion asks AeroSpace to run for
    /// terminal launches (AeroSpace owns the shortcut; the companion owns the launch logic).
    public func aerospaceCommand(launchCommand: String, pausedMode: String) -> String {
        switch self {
        case .launchTerminal: return "exec-and-forget \(launchCommand)"
        // `stop` keeps focus in place at a layout edge (the PRD requirement); it is
        // AeroSpace's default, written explicitly so the intent survives edits.
        // --ignore-floating: AeroSpace 0.21.3-Beta can trap (crash) in `focus` while temporarily
        // re-inserting floating windows into the tiling tree (makeFloatingWindowsSeenAsTiling).
        // Observed on-device; floating windows stay reachable with the mouse or the menu.
        case .focus(let d): return "focus --ignore-floating --boundaries workspace --boundaries-action stop \(d.rawValue)"
        case .move(let d): return "move \(d.rawValue)"
        case .switchWorkspace(let n): return "workspace \(n)"
        // No --focus-follows-window: the user stays in the current workspace.
        case .moveToWorkspace(let n): return "move-node-to-workspace \(n)"
        case .shrink: return "resize smart -50"
        case .grow: return "resize smart +50"
        case .toggleOrientation: return "layout tiles horizontal vertical"
        case .toggleFloating: return "layout floating tiling"
        case .focusNextMonitor: return "focus-monitor --wrap-around next"
        case .moveToNextMonitor: return "move-node-to-monitor --wrap-around next"
        case .resetLayout: return "flatten-workspace-tree"
        case .togglePause: return "mode \(pausedMode)"
        }
    }

    /// CLI arguments for running the action from the companion menu via the `aerospace` CLI.
    /// Returns nil for actions that are not AeroSpace commands.
    public var cliArguments: [String]? {
        switch self {
        case .launchTerminal, .togglePause: return nil
        default:
            return aerospaceCommand(launchCommand: "", pausedMode: "")
                .split(separator: " ").map(String.init)
        }
    }

    // Codable via the stable id.
    public init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        let s = try c.decode(String.self)
        guard let a = Action(id: s) else {
            throw DecodingError.dataCorruptedError(in: c, debugDescription: "Unknown action \(s)")
        }
        self = a
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        try c.encode(id)
    }
}
