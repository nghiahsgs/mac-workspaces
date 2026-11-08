import Foundation

/// Renders a complete AeroSpace configuration from the product settings.
///
/// AeroSpace does not merge `mode.*.binding` tables with its defaults, so the generated file
/// must contain every binding. The settings model is the single source of truth: editing a
/// shortcut in the companion re-renders this file.
public struct ConfigGenerator: Sendable {
    public static let managedMarker = "# Managed by mac-workspaces"
    public static let pausedMode = "paused"

    /// Shell command AeroSpace runs (via `exec-and-forget`) for the terminal shortcut.
    /// Opening the URL routes the request to the running companion through LaunchServices,
    /// so the companion — not AeroSpace — owns the Terminal Automation permission, the
    /// auto-repeat filter, and workspace placement checks. `-g` keeps the companion in the
    /// background.
    public static let defaultLaunchCommand = "/usr/bin/open -g '\(AppPaths.urlScheme)://launch-terminal'"

    public var launchCommand: String

    public init(launchCommand: String = ConfigGenerator.defaultLaunchCommand) {
        self.launchCommand = launchCommand
    }

    public func render(_ settings: Settings) -> String {
        var lines: [String] = []
        func add(_ s: String = "") { lines.append(s) }

        add("\(Self.managedMarker) (https://github.com/nghiahsgs/mac-workspaces).")
        add("# Edit shortcuts and workspace names in the mac-workspaces menu bar app.")
        add("# Manual edits are detected; the app will show a diff and back up this file")
        add("# before replacing it.")
        add()
        add("config-version = 2")
        add()
        add("start-at-login = \(settings.startAeroSpaceAtLogin)")
        add("after-startup-command = []")
        add("auto-reload-config = false")
        add()
        add("enable-normalization-flatten-containers = true")
        add("enable-normalization-opposite-orientation-for-nested-containers = true")
        add()
        add("accordion-padding = 30")
        add("default-root-container-layout = 'tiles'")
        add("# 'auto' = horizontal (side by side) on landscape displays, vertical on portrait.")
        add("default-root-container-orientation = '\(settings.orientation.rawValue)'")
        add()
        add("on-focused-monitor-changed = ['move-mouse monitor-lazy-center']")
        add("automatically-unhide-macos-hidden-apps = false")
        add()
        add("# Nine numbered AeroSpace virtual workspaces (separate from macOS Spaces).")
        let names = Action.workspaceNumbers.map { n -> String in
            let label = settings.displayName(forWorkspace: String(n))
            return label.map { "\(n)=\($0)" } ?? "\(n)"
        }
        add("# Display names (companion only): \(names.joined(separator: ", "))")
        add("persistent-workspaces = [\(Action.workspaceNumbers.map { "\"\($0)\"" }.joined(separator: ", "))]")
        add()
        add("key-mapping.preset = 'qwerty'")
        add()
        add("gaps.inner.horizontal = 0")
        add("gaps.inner.vertical = 0")
        add("gaps.outer.left = 0")
        add("gaps.outer.bottom = 0")
        add("gaps.outer.top = 0")
        add("gaps.outer.right = 0")
        add()

        // Floating rules: AeroSpace already floats windows it recognizes as dialogs.
        if !settings.floatingAppBundleIDs.isEmpty {
            add("# Utility apps that always float. Dialogs float automatically.")
            add("on-window-detected = [")
            for id in settings.floatingAppBundleIDs where Self.isSafeBundleID(id) {
                add("    { if = 'test %{app-bundle-id} = \(id)', run = 'layout floating' },")
            }
            add("]")
            add()
        }

        add("[mode.main.binding]")
        for (action, shortcut) in settings.effectiveBindings {
            guard let shortcut, KeyNames.isValid(shortcut.key) else { continue }
            let command = action.aerospaceCommand(launchCommand: launchCommand, pausedMode: Self.pausedMode)
            add("    \(shortcut.notation) = \(Self.tomlString(command))  # \(action.title)")
        }
        add()

        add("# Paused: product shortcuts stop intercepting keys; tiling keeps working.")
        add("# Resume from the menu bar (or the pause shortcut, if one is assigned).")
        add("[mode.\(Self.pausedMode).binding]")
        if let resume = settings.shortcut(for: .togglePause), KeyNames.isValid(resume.key) {
            add("    \(resume.notation) = 'mode main'  # Resume shortcuts")
        }
        add()
        return lines.joined(separator: "\n")
    }

    /// TOML literal string when possible, basic string with escapes otherwise.
    static func tomlString(_ s: String) -> String {
        if !s.contains("'") && !s.contains("\n") { return "'\(s)'" }
        let escaped = s
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\n", with: "\\n")
        return "\"\(escaped)\""
    }

    static func isSafeBundleID(_ id: String) -> Bool {
        !id.isEmpty && id.allSatisfy { $0.isLetter || $0.isNumber || $0 == "." || $0 == "-" || $0 == "_" }
    }

    public static func isManaged(_ contents: String) -> Bool {
        contents.hasPrefix(managedMarker)
    }
}
