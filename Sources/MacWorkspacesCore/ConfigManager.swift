import Foundation

/// Where AeroSpace's config lives and what state it is in.
public enum ConfigLocation: Equatable, Sendable {
    /// No config yet; we will create one at `url`.
    case none(proposed: URL)
    case found(URL)
    /// Both supported locations exist; AeroSpace reports this as ambiguous.
    case ambiguous([URL])
}

public enum ConfigState: Equatable, Sendable {
    case missing
    /// Our generated file, matching what we last wrote.
    case managedUnchanged
    /// Our generated file, edited by hand since.
    case managedEdited
    /// A config the user wrote themselves.
    case userOwned
}

public struct ConfigPlan: Equatable, Sendable {
    public let target: URL
    public let state: ConfigState
    public let currentContents: String?
    public let proposedContents: String
    public var hasChanges: Bool { currentContents != proposedContents }
    /// Applying needs the user to review a diff first (never silently replace).
    public var requiresReview: Bool { state == .userOwned || state == .managedEdited }
}

public enum ConfigError: LocalizedError, Equatable {
    case ambiguous([URL])
    case noBackups

    public var errorDescription: String? {
        switch self {
        case .ambiguous(let urls):
            return "AeroSpace found more than one config: " + urls.map(\.path).joined(separator: " and ") + ". Remove or rename one, then try again."
        case .noBackups:
            return "No backups found."
        }
    }
}

/// Plans, backs up, applies and restores AeroSpace configuration files.
public struct ConfigManager {
    public let homeDirectory: URL
    public let xdgConfigHome: URL?
    public let backupDirectory: URL
    public let stateURL: URL
    public let fileManager: FileManager
    public var now: () -> Date

    public init(
        homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser,
        xdgConfigHome: URL? = ProcessInfo.processInfo.environment["XDG_CONFIG_HOME"].map { URL(fileURLWithPath: $0) },
        supportDirectory: URL = AppPaths.supportDirectory(),
        fileManager: FileManager = .default,
        now: @escaping () -> Date = Date.init
    ) {
        self.homeDirectory = homeDirectory
        self.xdgConfigHome = xdgConfigHome
        self.backupDirectory = supportDirectory.appendingPathComponent("Backups", isDirectory: true)
        self.stateURL = supportDirectory.appendingPathComponent("last-applied-config.toml")
        self.fileManager = fileManager
        self.now = now
    }

    public var primaryPath: URL { homeDirectory.appendingPathComponent(".aerospace.toml") }
    public var xdgPath: URL {
        (xdgConfigHome ?? homeDirectory.appendingPathComponent(".config"))
            .appendingPathComponent("aerospace/aerospace.toml")
    }

    public func locate() -> ConfigLocation {
        let existing = [primaryPath, xdgPath].filter { fileManager.fileExists(atPath: $0.path) }
        switch existing.count {
        case 0: return .none(proposed: primaryPath)
        case 1: return .found(existing[0])
        default: return .ambiguous(existing)
        }
    }

    public func state(of contents: String?) -> ConfigState {
        guard let contents else { return .missing }
        guard ConfigGenerator.isManaged(contents) else { return .userOwned }
        let lastApplied = try? String(contentsOf: stateURL, encoding: .utf8)
        return lastApplied == contents ? .managedUnchanged : .managedEdited
    }

    public func plan(proposed: String) throws -> ConfigPlan {
        switch locate() {
        case .ambiguous(let urls):
            throw ConfigError.ambiguous(urls)
        case .none(let url):
            return ConfigPlan(target: url, state: .missing, currentContents: nil, proposedContents: proposed)
        case .found(let url):
            let contents = try String(contentsOf: url, encoding: .utf8)
            return ConfigPlan(target: url, state: state(of: contents), currentContents: contents, proposedContents: proposed)
        }
    }

    /// Writes the proposed config. Any existing file is backed up first.
    /// Returns the backup URL, if one was made.
    @discardableResult
    public func apply(_ plan: ConfigPlan) throws -> URL? {
        var backup: URL?
        if let current = plan.currentContents {
            backup = try makeBackup(contents: current, reason: "before-apply")
        }
        try fileManager.createDirectory(at: plan.target.deletingLastPathComponent(), withIntermediateDirectories: true)
        try plan.proposedContents.write(to: plan.target, atomically: true, encoding: .utf8)
        try recordApplied(plan.proposedContents)
        return backup
    }

    public func makeBackup(contents: String, reason: String) throws -> URL {
        try fileManager.createDirectory(at: backupDirectory, withIntermediateDirectories: true)
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        let stamp = formatter.string(from: now())
        var url = backupDirectory.appendingPathComponent("aerospace-\(stamp)-\(reason).toml")
        var n = 2
        while fileManager.fileExists(atPath: url.path) {
            url = backupDirectory.appendingPathComponent("aerospace-\(stamp)-\(reason)-\(n).toml")
            n += 1
        }
        try contents.write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    /// Backups, newest first.
    public func backups() -> [URL] {
        let urls = (try? fileManager.contentsOfDirectory(at: backupDirectory, includingPropertiesForKeys: nil)) ?? []
        return urls.filter { $0.pathExtension == "toml" }.sorted { $0.lastPathComponent > $1.lastPathComponent }
    }

    /// Restores a backup into the active config location. The current file is backed up
    /// first, so a restore can itself be undone.
    @discardableResult
    public func restore(_ backup: URL) throws -> URL {
        let contents = try String(contentsOf: backup, encoding: .utf8)
        let target: URL
        switch locate() {
        case .ambiguous(let urls): throw ConfigError.ambiguous(urls)
        case .none(let url): target = url
        case .found(let url):
            target = url
            let current = try String(contentsOf: url, encoding: .utf8)
            if current != contents { _ = try makeBackup(contents: current, reason: "before-restore") }
        }
        try contents.write(to: target, atomically: true, encoding: .utf8)
        if ConfigGenerator.isManaged(contents) { try recordApplied(contents) }
        return target
    }

    func recordApplied(_ contents: String) throws {
        try fileManager.createDirectory(at: stateURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try contents.write(to: stateURL, atomically: true, encoding: .utf8)
    }
}

/// Minimal line-based unified diff (LCS), enough to review config changes in the app.
public enum LineDiff {
    public enum Line: Equatable, Sendable {
        case same(String), added(String), removed(String)

        public var text: String {
            switch self {
            case .same(let s): return "  " + s
            case .added(let s): return "+ " + s
            case .removed(let s): return "- " + s
            }
        }
    }

    public static func diff(_ old: String, _ new: String) -> [Line] {
        let a = old.components(separatedBy: "\n")
        let b = new.components(separatedBy: "\n")
        let n = a.count, m = b.count
        var lcs = Array(repeating: Array(repeating: 0, count: m + 1), count: n + 1)
        for i in stride(from: n - 1, through: 0, by: -1) {
            for j in stride(from: m - 1, through: 0, by: -1) {
                lcs[i][j] = a[i] == b[j] ? lcs[i + 1][j + 1] + 1 : max(lcs[i + 1][j], lcs[i][j + 1])
            }
        }
        var result: [Line] = []
        var i = 0, j = 0
        while i < n && j < m {
            if a[i] == b[j] { result.append(.same(a[i])); i += 1; j += 1 }
            else if lcs[i + 1][j] >= lcs[i][j + 1] { result.append(.removed(a[i])); i += 1 }
            else { result.append(.added(b[j])); j += 1 }
        }
        while i < n { result.append(.removed(a[i])); i += 1 }
        while j < m { result.append(.added(b[j])); j += 1 }
        return result
    }

    public static func render(_ old: String?, _ new: String) -> String {
        guard let old else { return new.components(separatedBy: "\n").map { "+ " + $0 }.joined(separator: "\n") }
        return diff(old, new).map(\.text).joined(separator: "\n")
    }
}
