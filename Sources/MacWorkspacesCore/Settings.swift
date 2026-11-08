import Foundation

public enum TilingOrientation: String, Codable, CaseIterable, Sendable {
    /// Horizontal on landscape displays, vertical on portrait ones.
    case auto
    case horizontal
    case vertical

    public var title: String {
        switch self {
        case .auto: return "Automatic (horizontal on landscape displays)"
        case .horizontal: return "Horizontal (side by side)"
        case .vertical: return "Vertical (stacked)"
        }
    }
}

/// Product preferences, stored locally as JSON. No account, backend, or telemetry.
public struct Settings: Codable, Equatable, Sendable {
    public static let currentVersion = 1

    public var version: Int = Settings.currentVersion
    /// Optional display names keyed by workspace number ("1"..."9").
    public var workspaceNames: [String: String] = ["1": "Code", "2": "Web", "3": "Chat"]
    /// Shortcut per action id. An action missing from the map uses its default;
    /// an explicit empty string means "unbound".
    public var bindings: [String: String] = [:]
    public var orientation: TilingOrientation = .auto
    public var startAeroSpaceAtLogin: Bool = true
    /// Apps (bundle ids) that always float, in addition to AeroSpace's dialog detection.
    public var floatingAppBundleIDs: [String] = [
        "com.apple.systempreferences",
        "com.apple.calculator",
        "com.apple.ScreenSharing",
    ]
    /// Set once the user has reviewed bindings and applied a configuration.
    public var setupCompleted: Bool = false

    public init() {}

    public static let `default` = Settings()

    public func shortcut(for action: Action) -> Shortcut? {
        guard let stored = bindings[action.id] else { return action.defaultShortcut }
        if stored.isEmpty { return nil }
        return Shortcut(notation: stored) ?? action.defaultShortcut
    }

    public mutating func setShortcut(_ shortcut: Shortcut?, for action: Action) {
        if shortcut == action.defaultShortcut {
            bindings.removeValue(forKey: action.id)
        } else {
            bindings[action.id] = shortcut?.notation ?? ""
        }
    }

    public mutating func resetBindings() { bindings = [:] }

    /// All effective bindings in display order.
    public var effectiveBindings: [(action: Action, shortcut: Shortcut?)] {
        Action.allCases.map { ($0, shortcut(for: $0)) }
    }

    public func displayName(forWorkspace workspace: String) -> String? {
        guard let name = workspaceNames[workspace]?.trimmingCharacters(in: .whitespaces), !name.isEmpty else {
            return nil
        }
        return name
    }

    /// "2 · Web" or just "2".
    public func label(forWorkspace workspace: String) -> String {
        if let name = displayName(forWorkspace: workspace) { return "\(workspace) · \(name)" }
        return workspace
    }

    // Tolerant decoding so older/newer settings files never fail to load.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = Settings()
        version = try c.decodeIfPresent(Int.self, forKey: .version) ?? d.version
        workspaceNames = try c.decodeIfPresent([String: String].self, forKey: .workspaceNames) ?? d.workspaceNames
        bindings = try c.decodeIfPresent([String: String].self, forKey: .bindings) ?? d.bindings
        orientation = (try? c.decodeIfPresent(TilingOrientation.self, forKey: .orientation)) ?? d.orientation
        startAeroSpaceAtLogin = try c.decodeIfPresent(Bool.self, forKey: .startAeroSpaceAtLogin) ?? d.startAeroSpaceAtLogin
        floatingAppBundleIDs = try c.decodeIfPresent([String].self, forKey: .floatingAppBundleIDs) ?? d.floatingAppBundleIDs
        setupCompleted = try c.decodeIfPresent(Bool.self, forKey: .setupCompleted) ?? d.setupCompleted
    }
}

/// Reads and writes settings.json atomically.
public struct SettingsStore: Sendable {
    public let url: URL

    public init(url: URL) { self.url = url }

    public static func defaultStore(fileManager: FileManager = .default) -> SettingsStore {
        SettingsStore(url: AppPaths.supportDirectory(fileManager: fileManager).appendingPathComponent("settings.json"))
    }

    public func load() -> Settings {
        guard let data = try? Data(contentsOf: url),
              let settings = try? JSONDecoder().decode(Settings.self, from: data) else {
            return Settings()
        }
        return settings
    }

    public func save(_ settings: Settings) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(settings).write(to: url, options: .atomic)
    }
}

public enum AppPaths {
    public static let bundleIdentifier = "com.nghiahsgs.MacWorkspaces"
    public static let urlScheme = "macworkspaces"

    public static func supportDirectory(fileManager: FileManager = .default) -> URL {
        let base = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? fileManager.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support")
        return base.appendingPathComponent("MacWorkspaces", isDirectory: true)
    }
}
