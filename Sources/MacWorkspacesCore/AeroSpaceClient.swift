import Foundation

public struct WindowInfo: Equatable, Hashable, Sendable {
    public let id: Int
    public let workspace: String
    public let appBundleID: String

    public init(id: Int, workspace: String, appBundleID: String) {
        self.id = id
        self.workspace = workspace
        self.appBundleID = appBundleID
    }
}

public struct WorkspaceSnapshot: Equatable, Sendable {
    public var focused: String?
    public var occupied: Set<String>
    public var mode: String?

    public init(focused: String?, occupied: Set<String>, mode: String? = nil) {
        self.focused = focused
        self.occupied = occupied
        self.mode = mode
    }
}

public enum AeroSpaceError: LocalizedError, Equatable {
    case notInstalled
    case commandFailed(command: String, status: Int32, output: String)

    public var errorDescription: String? {
        switch self {
        case .notInstalled:
            return "The aerospace command-line tool was not found. Install AeroSpace first."
        case .commandFailed(let command, let status, let output):
            let detail = output.trimmingCharacters(in: .whitespacesAndNewlines)
            return "aerospace \(command) failed (exit \(status))" + (detail.isEmpty ? "" : ": \(detail)")
        }
    }
}

/// The boundary to AeroSpace. Everything the companion needs goes through this protocol
/// so the core logic can be tested without AeroSpace installed.
public protocol AeroSpaceControlling: Sendable {
    func run(_ arguments: [String]) throws -> String
}

public extension AeroSpaceControlling {
    func version() throws -> String {
        try run(["--version"]).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func focusedWorkspace() throws -> String {
        try run(["list-workspaces", "--focused"]).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func occupiedWorkspaces() throws -> Set<String> {
        let out = try run(["list-workspaces", "--monitor", "all", "--empty", "no"])
        return Set(AeroSpaceParsing.lines(out))
    }

    func currentMode() throws -> String {
        try run(["list-modes", "--current"]).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func snapshot() throws -> WorkspaceSnapshot {
        WorkspaceSnapshot(
            focused: try focusedWorkspace(),
            occupied: try occupiedWorkspaces(),
            mode: try? currentMode()
        )
    }

    func windows(appBundleID: String) throws -> [WindowInfo] {
        let out = try run([
            // `--all` accepts no filters; `--monitor all` is its documented equivalent that does.
            "list-windows", "--monitor", "all", "--app-bundle-id", appBundleID,
            "--format", AeroSpaceParsing.windowFormat,
        ])
        return AeroSpaceParsing.windows(out)
    }

    func switchWorkspace(_ name: String) throws { _ = try run(["workspace", name]) }
    func setMode(_ mode: String) throws { _ = try run(["mode", mode]) }
    func reloadConfig() throws { _ = try run(["reload-config", "--no-gui"]) }
    func validateConfig() throws { _ = try run(["reload-config", "--no-gui", "--dry-run"]) }

    func moveWindow(_ id: Int, toWorkspace workspace: String) throws {
        _ = try run(["move-node-to-workspace", "--window-id", String(id), workspace])
    }

    /// `--ignore-floating` avoids an AeroSpace 0.21.3-Beta crash path (see Action.focus).
    func focusWindow(_ id: Int) throws { _ = try run(["focus", "--ignore-floating", "--window-id", String(id)]) }
}

public enum AeroSpaceParsing {
    static let separator = "\t"
    public static let windowFormat = "%{window-id}%{tab}%{workspace}%{tab}%{app-bundle-id}"

    public static func lines(_ output: String) -> [String] {
        output.split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }

    public static func windows(_ output: String) -> [WindowInfo] {
        lines(output).compactMap { line in
            let parts = line.components(separatedBy: separator).map { $0.trimmingCharacters(in: .whitespaces) }
            guard parts.count >= 3, let id = Int(parts[0]) else { return nil }
            return WindowInfo(id: id, workspace: parts[1], appBundleID: parts[2])
        }
    }
}

/// Runs the real `aerospace` CLI.
public struct AeroSpaceCLI: AeroSpaceControlling {
    public static let candidatePaths = [
        "/opt/homebrew/bin/aerospace",
        "/usr/local/bin/aerospace",
        "/Applications/AeroSpace.app/Contents/MacOS/aerospace",
    ]

    public let executable: URL?
    public let timeout: TimeInterval

    public init(executable: URL? = AeroSpaceCLI.locate(), timeout: TimeInterval = 3) {
        self.executable = executable
        self.timeout = timeout
    }

    public static func locate(fileManager: FileManager = .default) -> URL? {
        var paths = candidatePaths
        if let pathEnv = ProcessInfo.processInfo.environment["PATH"] {
            paths += pathEnv.split(separator: ":").map { "\($0)/aerospace" }
        }
        return paths.first(where: { fileManager.isExecutableFile(atPath: $0) }).map(URL.init(fileURLWithPath:))
    }

    public func run(_ arguments: [String]) throws -> String {
        guard let executable else { throw AeroSpaceError.notInstalled }
        let process = Process()
        process.executableURL = executable
        process.arguments = arguments
        let out = Pipe()
        process.standardOutput = out
        process.standardError = out
        try process.run()

        let group = DispatchGroup()
        group.enter()
        var data = Data()
        DispatchQueue.global().async {
            data = out.fileHandleForReading.readDataToEndOfFile()
            group.leave()
        }
        if group.wait(timeout: .now() + timeout) == .timedOut {
            process.terminate()
            throw AeroSpaceError.commandFailed(command: arguments.joined(separator: " "), status: -1, output: "timed out")
        }
        process.waitUntilExit()
        let text = String(decoding: data, as: UTF8.self)
        guard process.terminationStatus == 0 else {
            throw AeroSpaceError.commandFailed(command: arguments.joined(separator: " "), status: process.terminationStatus, output: text)
        }
        return text
    }
}
