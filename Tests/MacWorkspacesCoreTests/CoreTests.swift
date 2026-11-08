import XCTest
@testable import MacWorkspacesCore

final class ShortcutTests: XCTestCase {
    func testParsesAndRendersCanonicalOrder() {
        let s = Shortcut(notation: "shift-alt-h")
        XCTAssertEqual(s?.notation, "alt-shift-h")
        XCTAssertEqual(s?.symbolLabel, "⌥⇧H")
        XCTAssertEqual(Shortcut(notation: "cmd-enter")?.spokenLabel, "Command + Return")
    }

    func testRejectsMalformed() {
        XCTAssertNil(Shortcut(notation: ""))
        XCTAssertNil(Shortcut(notation: "alt-"))
        XCTAssertNil(Shortcut(notation: "hyper-h"))
        XCTAssertNil(Shortcut(notation: "alt-alt-h"))
    }

    func testCodableAsString() throws {
        let data = try JSONEncoder().encode([Shortcut([.alt, .shift], "1")])
        XCTAssertEqual(String(decoding: data, as: UTF8.self), "[\"alt-shift-1\"]")
        XCTAssertEqual(try JSONDecoder().decode([Shortcut].self, from: data), [Shortcut([.alt, .shift], "1")])
    }
}

final class ActionTests: XCTestCase {
    func testDefaultsMatchPRD() {
        XCTAssertEqual(Action.launchTerminal.defaultShortcut?.notation, "cmd-enter")
        XCTAssertEqual(Action.focus(.left).defaultShortcut?.notation, "alt-h")
        XCTAssertEqual(Action.focus(.down).defaultShortcut?.notation, "alt-j")
        XCTAssertEqual(Action.move(.right).defaultShortcut?.notation, "alt-shift-l")
        XCTAssertEqual(Action.switchWorkspace(4).defaultShortcut?.notation, "alt-4")
        XCTAssertEqual(Action.moveToWorkspace(9).defaultShortcut?.notation, "alt-shift-9")
        XCTAssertEqual(Action.shrink.defaultShortcut?.notation, "alt-minus")
        XCTAssertEqual(Action.grow.defaultShortcut?.notation, "alt-equal")
        XCTAssertEqual(Action.toggleOrientation.defaultShortcut?.notation, "alt-slash")
        XCTAssertNil(Action.toggleFloating.defaultShortcut, "floating is menu-only by default")
    }

    func testIDsAreUniqueAndRoundTrip() {
        let ids = Action.allCases.map(\.id)
        XCTAssertEqual(ids.count, Set(ids).count)
        for a in Action.allCases { XCTAssertEqual(Action(id: a.id), a) }
    }

    func testMoveToWorkspaceDoesNotFollow() {
        let cmd = Action.moveToWorkspace(3).aerospaceCommand(launchCommand: "x", pausedMode: "p")
        XCTAssertEqual(cmd, "move-node-to-workspace 3")
        XCTAssertFalse(cmd.contains("focus-follows-window"))
    }

    func testFocusStopsAtEdge() {
        XCTAssertEqual(Action.focus(.up).aerospaceCommand(launchCommand: "", pausedMode: ""),
                       "focus --boundaries workspace --boundaries-action stop up")
    }

    func testCLIArguments() {
        XCTAssertEqual(Action.toggleFloating.cliArguments, ["layout", "floating", "tiling"])
        XCTAssertNil(Action.launchTerminal.cliArguments)
    }
}

final class SettingsTests: XCTestCase {
    func testOverridesAndUnbinding() {
        var s = Settings()
        XCTAssertEqual(s.shortcut(for: .focus(.left))?.notation, "alt-h")
        s.setShortcut(Shortcut([.ctrl], "left"), for: .focus(.left))
        XCTAssertEqual(s.shortcut(for: .focus(.left))?.notation, "ctrl-left")
        s.setShortcut(nil, for: .launchTerminal)
        XCTAssertNil(s.shortcut(for: .launchTerminal))
        s.setShortcut(Action.focus(.left).defaultShortcut, for: .focus(.left))
        XCTAssertNil(s.bindings["focus-left"], "resetting to default removes the override")
    }

    func testPersistsAcrossRestart() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let store = SettingsStore(url: dir.appendingPathComponent("settings.json"))
        var s = Settings()
        s.workspaceNames["4"] = "Music"
        s.setShortcut(Shortcut([.ctrl, .alt], "t"), for: .launchTerminal)
        s.orientation = .vertical
        try store.save(s)
        XCTAssertEqual(store.load(), s)
    }

    func testTolerantDecoding() throws {
        let json = #"{"workspaceNames":{"1":"Dev"},"orientation":"diagonal"}"#
        let s = try JSONDecoder().decode(Settings.self, from: Data(json.utf8))
        XCTAssertEqual(s.workspaceNames, ["1": "Dev"])
        XCTAssertEqual(s.orientation, .auto)
        XCTAssertEqual(s.shortcut(for: .launchTerminal)?.notation, "cmd-enter")
    }

    func testWorkspaceLabels() {
        var s = Settings()
        XCTAssertEqual(s.label(forWorkspace: "2"), "2 · Web")
        s.workspaceNames["2"] = "  "
        XCTAssertEqual(s.label(forWorkspace: "2"), "2")
    }
}

final class BindingValidatorTests: XCTestCase {
    func testDefaultsHaveNoErrors() {
        XCTAssertEqual(BindingValidator.errors(in: Settings()), [])
    }

    func testDefaultsWarnAboutCmdEnterAndOptionKeys() {
        let issues = BindingValidator.validate(Settings())
        XCTAssertTrue(issues.contains { if case .systemShortcut(.launchTerminal, _, _) = $0.kind { return true }; return false })
        XCTAssertEqual(issues.filter { if case .optionCharacter = $0.kind { return true }; return false }.count, 1)
    }

    func testDetectsDuplicates() {
        var s = Settings()
        s.setShortcut(Shortcut([.alt], "h"), for: .grow)
        let errors = BindingValidator.errors(in: s)
        XCTAssertEqual(errors.count, 1)
        guard case .duplicate(let shortcut, let actions) = errors[0].kind else { return XCTFail() }
        XCTAssertEqual(shortcut.notation, "alt-h")
        XCTAssertEqual(Set(actions), [.focus(.left), .grow])
    }

    func testDetectsInvalidKeyAndMissingModifier() {
        var s = Settings()
        s.bindings["grow"] = "alt-plus"
        s.bindings["shrink"] = "q"
        let errors = BindingValidator.errors(in: s)
        XCTAssertTrue(errors.contains(BindingIssue(kind: .invalidKey(.grow, "plus"))))
        XCTAssertTrue(errors.contains(BindingIssue(kind: .noModifier(.shrink, Shortcut([], "q")))))
    }
}

final class ConfigGeneratorTests: XCTestCase {
    let output = ConfigGenerator().render(Settings())

    func testManagedHeaderAndVersion() {
        XCTAssertTrue(output.hasPrefix(ConfigGenerator.managedMarker))
        XCTAssertTrue(ConfigGenerator.isManaged(output))
        XCTAssertTrue(output.contains("config-version = 2"))
        XCTAssertTrue(output.contains("persistent-workspaces = [\"1\", \"2\", \"3\", \"4\", \"5\", \"6\", \"7\", \"8\", \"9\"]"))
        XCTAssertTrue(output.contains("default-root-container-orientation = 'auto'"))
    }

    func testBindings() {
        XCTAssertTrue(output.contains("cmd-enter = \"exec-and-forget /usr/bin/open -g 'macworkspaces://launch-terminal'\""))
        XCTAssertTrue(output.contains("alt-h = 'focus --boundaries workspace --boundaries-action stop left'"))
        XCTAssertTrue(output.contains("alt-shift-3 = 'move-node-to-workspace 3'"))
        XCTAssertTrue(output.contains("alt-slash = 'layout tiles horizontal vertical'"))
        XCTAssertTrue(output.contains("alt-minus = 'resize smart -50'"))
    }

    func testEveryBoundActionAppearsExactlyOnce() {
        let bindingLines = output.components(separatedBy: "\n").filter { $0.hasPrefix("    ") && $0.contains(" = ") && !$0.contains("if =") }
        let bound = Settings().effectiveBindings.compactMap(\.shortcut)
        XCTAssertEqual(bindingLines.count, bound.count)
    }

    func testPausedModeIsEmptyUnlessResumeBound() {
        let paused = output.components(separatedBy: "[mode.paused.binding]")[1]
        XCTAssertFalse(paused.contains(" = "))

        var s = Settings()
        s.setShortcut(Shortcut([.ctrl, .alt], "p"), for: .togglePause)
        let out = ConfigGenerator().render(s)
        XCTAssertTrue(out.contains("alt-ctrl-p = 'mode paused'"))
        XCTAssertTrue(out.components(separatedBy: "[mode.paused.binding]")[1].contains("alt-ctrl-p = 'mode main'"))
    }

    func testFloatingRules() {
        XCTAssertTrue(output.contains("{ if = 'test %{app-bundle-id} = com.apple.systempreferences', run = 'layout floating' },"))
        var s = Settings()
        s.floatingAppBundleIDs = ["evil'; rm -rf ~"]
        XCTAssertFalse(ConfigGenerator().render(s).contains("evil"))
    }

    func testUnboundAndInvalidAreSkipped() {
        var s = Settings()
        s.setShortcut(nil, for: .launchTerminal)
        s.bindings["grow"] = "alt-plus"
        let out = ConfigGenerator().render(s)
        XCTAssertFalse(out.contains("launch-terminal'"))
        XCTAssertFalse(out.contains("alt-plus"))
    }

    func testTomlStringEscaping() {
        XCTAssertEqual(ConfigGenerator.tomlString("a b"), "'a b'")
        XCTAssertEqual(ConfigGenerator.tomlString("it's \"x\""), "\"it's \\\"x\\\"\"")
    }
}

final class ConfigManagerTests: XCTestCase {
    var home: URL!
    var support: URL!
    var manager: ConfigManager!

    override func setUpWithError() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        home = root.appendingPathComponent("home")
        support = root.appendingPathComponent("support")
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
        var tick = 0.0
        manager = ConfigManager(homeDirectory: home, xdgConfigHome: nil, supportDirectory: support, now: {
            tick += 1
            return Date(timeIntervalSince1970: 1_800_000_000 + tick)
        })
    }

    func testCleanSetupWritesWithoutBackup() throws {
        let plan = try manager.plan(proposed: "# Managed by mac-workspaces\nx = 1")
        XCTAssertEqual(plan.state, .missing)
        XCTAssertFalse(plan.requiresReview)
        XCTAssertNil(try manager.apply(plan))
        XCTAssertEqual(try String(contentsOf: manager.primaryPath, encoding: .utf8), "# Managed by mac-workspaces\nx = 1")
        XCTAssertEqual(manager.state(of: try String(contentsOf: manager.primaryPath, encoding: .utf8)), .managedUnchanged)
    }

    func testExistingUserConfigRequiresReviewAndIsBackedUp() throws {
        try "my = 'config'".write(to: manager.primaryPath, atomically: true, encoding: .utf8)
        let plan = try manager.plan(proposed: "# Managed by mac-workspaces\nnew = 1")
        XCTAssertEqual(plan.state, .userOwned)
        XCTAssertTrue(plan.requiresReview)
        let backup = try XCTUnwrap(try manager.apply(plan))
        XCTAssertEqual(try String(contentsOf: backup, encoding: .utf8), "my = 'config'")
        XCTAssertEqual(manager.backups().map(\.lastPathComponent), [backup.lastPathComponent])
    }

    func testHandEditedManagedConfigRequiresReview() throws {
        try manager.apply(try manager.plan(proposed: "# Managed by mac-workspaces\nv = 1"))
        try "# Managed by mac-workspaces\nv = 2".write(to: manager.primaryPath, atomically: true, encoding: .utf8)
        let plan = try manager.plan(proposed: "# Managed by mac-workspaces\nv = 3")
        XCTAssertEqual(plan.state, .managedEdited)
        XCTAssertTrue(plan.requiresReview)
    }

    func testRestoreBacksUpCurrentFirst() throws {
        try "original".write(to: manager.primaryPath, atomically: true, encoding: .utf8)
        let backup = try XCTUnwrap(try manager.apply(try manager.plan(proposed: "# Managed by mac-workspaces\n")))
        try manager.restore(backup)
        XCTAssertEqual(try String(contentsOf: manager.primaryPath, encoding: .utf8), "original")
        XCTAssertEqual(manager.backups().count, 2, "the generated config was backed up before restoring")
    }

    func testUsesXDGLocationWhenThatIsTheOnlyConfig() throws {
        try FileManager.default.createDirectory(at: manager.xdgPath.deletingLastPathComponent(), withIntermediateDirectories: true)
        try "x".write(to: manager.xdgPath, atomically: true, encoding: .utf8)
        XCTAssertEqual(manager.locate(), .found(manager.xdgPath))
    }

    func testAmbiguousLocationsAreRefused() throws {
        try FileManager.default.createDirectory(at: manager.xdgPath.deletingLastPathComponent(), withIntermediateDirectories: true)
        try "x".write(to: manager.xdgPath, atomically: true, encoding: .utf8)
        try "y".write(to: manager.primaryPath, atomically: true, encoding: .utf8)
        XCTAssertThrowsError(try manager.plan(proposed: "z")) { error in
            guard case ConfigError.ambiguous = error else { return XCTFail("\(error)") }
        }
    }

    func testDiff() {
        let d = LineDiff.diff("a\nb\nc", "a\nx\nc")
        XCTAssertEqual(d, [.same("a"), .removed("b"), .added("x"), .same("c")])
        XCTAssertEqual(LineDiff.render(nil, "n"), "+ n")
    }
}

final class LaunchGateTests: XCTestCase {
    let t0 = Date(timeIntervalSince1970: 0)

    func testKeyStateIgnoresAutoRepeatUntilRelease() {
        let gate = LaunchGate(observesKeyState: true)
        XCTAssertTrue(gate.shouldAccept(at: t0))
        // Holding the key: initial repeat delay then rapid repeats.
        for ms in stride(from: 500, through: 2000, by: 33) {
            XCTAssertFalse(gate.shouldAccept(at: t0.addingTimeInterval(Double(ms) / 1000)))
        }
        gate.keyReleased()
        XCTAssertTrue(gate.shouldAccept(at: t0.addingTimeInterval(2.2)))
    }

    func testThreeDeliberatePressesCreateThreeWindows() {
        let gate = LaunchGate(observesKeyState: true)
        var accepted = 0
        for i in 0..<3 {
            if gate.shouldAccept(at: t0.addingTimeInterval(Double(i) * 0.12)) { accepted += 1 }
            gate.keyReleased()
        }
        XCTAssertEqual(accepted, 3)
    }

    func testDisarmTimeoutRecovers() {
        let gate = LaunchGate(observesKeyState: true, disarmTimeout: 5)
        XCTAssertTrue(gate.shouldAccept(at: t0))
        XCTAssertTrue(gate.shouldAccept(at: t0.addingTimeInterval(6)))
    }

    func testTimingFallbackSuppressesRepeatStream() {
        let gate = LaunchGate(observesKeyState: false)
        XCTAssertTrue(gate.shouldAccept(at: t0))
        // A continuous stream of requests 30 ms apart stays suppressed (sliding window).
        // Limitation: timing alone cannot tell the first repeat after the OS initial-repeat
        // delay from a deliberate press, which is why key-state observation is preferred.
        for i in 1...30 { XCTAssertFalse(gate.shouldAccept(at: t0.addingTimeInterval(Double(i) * 0.03))) }
        // Next deliberate press after a pause is accepted.
        XCTAssertTrue(gate.shouldAccept(at: t0.addingTimeInterval(2.0)))
        XCTAssertTrue(gate.shouldAccept(at: t0.addingTimeInterval(2.3)))
    }
}

// MARK: - Fakes

final class FakeAeroSpace: AeroSpaceControlling, @unchecked Sendable {
    var focused = "1"
    var windows: [WindowInfo] = []
    var log: [[String]] = []
    /// Called after each `list-windows` to simulate a window appearing.
    var onListWindows: (() -> Void)?
    var failAll = false

    func run(_ arguments: [String]) throws -> String {
        log.append(arguments)
        if failAll { throw AeroSpaceError.notInstalled }
        switch arguments.first {
        case "list-workspaces" where arguments.contains("--focused"): return focused + "\n"
        case "list-workspaces": return Set(windows.map(\.workspace)).sorted().joined(separator: "\n")
        case "list-windows":
            let out = windows.map { "\($0.id)\t\($0.workspace)\t\($0.appBundleID)" }.joined(separator: "\n")
            onListWindows?()
            return out
        case "move-node-to-workspace":
            let id = Int(arguments[2])!, ws = arguments[3]
            windows = windows.map { $0.id == id ? WindowInfo(id: id, workspace: ws, appBundleID: $0.appBundleID) : $0 }
            return ""
        default: return ""
        }
    }
}

final class FakeTerminal: TerminalAdapter, @unchecked Sendable {
    let displayName = "Terminal"
    let bundleIdentifier = "com.apple.Terminal"
    var opened = 0
    var onOpen: (() -> Void)?
    func openNewWindow() throws { opened += 1; onOpen?() }
}

final class TerminalLauncherTests: XCTestCase {
    func makeLauncher(_ a: FakeAeroSpace, _ t: FakeTerminal) -> TerminalLauncher {
        TerminalLauncher(aerospace: a, terminal: t, detectionTimeout: 1, pollInterval: 0.001, sleep: { _ in })
    }

    func testNewWindowInTargetIsFocused() throws {
        let a = FakeAeroSpace(), t = FakeTerminal()
        a.windows = [WindowInfo(id: 1, workspace: "1", appBundleID: t.bundleIdentifier)]
        t.onOpen = { a.windows.append(WindowInfo(id: 7, workspace: "1", appBundleID: t.bundleIdentifier)) }
        let r = try makeLauncher(a, t).launch(targetWorkspace: "1")
        XCTAssertEqual(r.windowID, 7)
        XCTAssertEqual(r.placement, .inTarget)
        XCTAssertTrue(a.log.contains(["focus", "--window-id", "7"]))
        XCTAssertEqual(t.opened, 1)
    }

    func testWindowLandingInWrongWorkspaceIsMovedBack() throws {
        let a = FakeAeroSpace(), t = FakeTerminal()
        a.focused = "2"
        // User pressed the shortcut on workspace 2, then switched to 5 before the window appeared.
        t.onOpen = {
            a.focused = "5"
            a.windows.append(WindowInfo(id: 9, workspace: "5", appBundleID: t.bundleIdentifier))
        }
        let r = try makeLauncher(a, t).launch(targetWorkspace: "2")
        XCTAssertEqual(r.placement, .corrected(from: "5"))
        XCTAssertTrue(a.log.contains(["move-node-to-workspace", "--window-id", "9", "2"]))
        XCTAssertFalse(a.log.contains(["focus", "--window-id", "9"]), "does not yank the user back")
        XCTAssertEqual(a.windows.first?.workspace, "2")
    }

    func testDelayedWindowIsDetected() throws {
        let a = FakeAeroSpace(), t = FakeTerminal()
        var calls = 0
        a.onListWindows = {
            calls += 1
            if calls == 4 { a.windows.append(WindowInfo(id: 3, workspace: "1", appBundleID: t.bundleIdentifier)) }
        }
        let r = try makeLauncher(a, t).launch(targetWorkspace: "1")
        XCTAssertEqual(r.windowID, 3)
    }

    func testNotDetected() throws {
        let a = FakeAeroSpace(), t = FakeTerminal()
        final class Clock: @unchecked Sendable { var now = Date(timeIntervalSince1970: 0) }
        let clock = Clock()
        let launcher = TerminalLauncher(aerospace: a, terminal: t, detectionTimeout: 1, pollInterval: 0.1,
                                        sleep: { _ in }, clock: { clock.now = clock.now.addingTimeInterval(0.1); return clock.now })
        XCTAssertEqual(try launcher.launch(targetWorkspace: "1").placement, .notDetected)
        XCTAssertEqual(t.opened, 1)
    }

    func testStillOpensWhenAeroSpaceUnavailable() throws {
        let a = FakeAeroSpace(), t = FakeTerminal()
        a.failAll = true
        let launcher = makeLauncher(a, t)
        let r = try launcher.launch(targetWorkspace: launcher.currentWorkspace())
        XCTAssertEqual(r.placement, .unverified)
        XCTAssertEqual(t.opened, 1)
    }
}

final class ParsingTests: XCTestCase {
    func testWindows() {
        let out = "12\t1\tcom.apple.Terminal\n\n 13 \t 2 \t com.apple.Terminal \ngarbage\n"
        XCTAssertEqual(AeroSpaceParsing.windows(out), [
            WindowInfo(id: 12, workspace: "1", appBundleID: "com.apple.Terminal"),
            WindowInfo(id: 13, workspace: "2", appBundleID: "com.apple.Terminal"),
        ])
    }

    func testSnapshot() throws {
        let a = FakeAeroSpace()
        a.focused = "3"
        a.windows = [WindowInfo(id: 1, workspace: "1", appBundleID: "x"), WindowInfo(id: 2, workspace: "3", appBundleID: "y")]
        let snap = try a.snapshot()
        XCTAssertEqual(snap.focused, "3")
        XCTAssertEqual(snap.occupied, ["1", "3"])
    }
}
