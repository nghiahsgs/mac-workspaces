import AppKit
import Combine
import SwiftUI
import MacWorkspacesCore

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    let model = AppModel()
    private var statusItem: NSStatusItem!
    private var cancellables: Set<AnyCancellable> = []
    private var windows: [String: NSWindow] = [:]

    func applicationWillFinishLaunching(_ notification: Notification) {
        // Register before launch finishes so a URL that launched us is not missed.
        NSAppleEventManager.shared().setEventHandler(
            self, andSelector: #selector(handleURLEvent(_:withReply:)),
            forEventClass: AEEventClass(kInternetEventClass), andEventID: AEEventID(kAEGetURL)
        )
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.toolTip = "mac-workspaces"
        let menu = NSMenu()
        menu.delegate = self
        statusItem.menu = menu

        model.objectWillChange
            .receive(on: RunLoop.main)
            .sink { [weak self] in DispatchQueue.main.async { self?.updateStatusButton() } }
            .store(in: &cancellables)
        model.$lastMessage
            .compactMap { $0 }
            .receive(on: RunLoop.main)
            .sink { message in Notifier.show(message) }
            .store(in: &cancellables)

        model.start()
        updateStatusButton()
        if !model.settings.setupCompleted { showSetup() }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showSettings()
        return false
    }

    @objc private func handleURLEvent(_ event: NSAppleEventDescriptor, withReply reply: NSAppleEventDescriptor) {
        guard let string = event.paramDescriptor(forKeyword: AEKeyword(keyDirectObject))?.stringValue,
              let url = URL(string: string), url.scheme == AppPaths.urlScheme else { return }
        switch url.host {
        case "launch-terminal": model.requestTerminalLaunch()
        case "refresh": model.refreshWorkspaces()
        case "settings": showSettings()
        case "setup": showSetup()
        default: break
        }
    }

    // MARK: Status button

    private func updateStatusButton() {
        guard let button = statusItem?.button else { return }
        button.attributedTitle = StatusTitle.make(model: model)
    }

    // MARK: Menu

    func menuNeedsUpdate(_ menu: NSMenu) {
        model.refreshWorkspaces()
        menu.removeAllItems()

        if let problem = model.statusProblem {
            let item = NSMenuItem(title: "⚠︎ \(problem) — Open Setup…", action: #selector(openSetup), keyEquivalent: "")
            item.target = self
            menu.addItem(item)
            menu.addItem(.separator())
        }
        if model.isPaused {
            menu.addItem(disabled("Shortcuts paused"))
        }

        menu.addItem(disabled("Workspaces"))
        for n in Action.workspaceNumbers {
            let name = String(n)
            let occupied = model.snapshot.occupied.contains(name)
            let item = NSMenuItem(title: model.settings.label(forWorkspace: name) + (occupied ? "" : "  (empty)"),
                                  action: #selector(switchWorkspace(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = name
            item.state = model.snapshot.focused == name ? .on : .off
            item.isEnabled = model.aerospaceReachable
            if let s = model.settings.shortcut(for: .switchWorkspace(n)) { applyShortcutHint(s, to: item) }
            menu.addItem(item)
        }
        menu.addItem(.separator())

        menu.addItem(actionItem(.launchTerminal, title: "New Terminal Window"))
        let windowMenu = NSMenu()
        for action in [Action.toggleFloating, .toggleOrientation, .resetLayout, .focusNextMonitor, .moveToNextMonitor] {
            windowMenu.addItem(actionItem(action, title: action.title))
        }
        let windowItem = NSMenuItem(title: "Window", action: nil, keyEquivalent: "")
        windowItem.submenu = windowMenu
        menu.addItem(windowItem)
        menu.addItem(.separator())

        let pause = NSMenuItem(title: model.isPaused ? "Resume Shortcuts" : "Pause Shortcuts", action: #selector(togglePause), keyEquivalent: "")
        pause.target = self
        pause.isEnabled = model.aerospaceReachable
        menu.addItem(pause)
        menu.addItem(item("Shortcut Reference…", #selector(openReference)))
        menu.addItem(item("Setup…", #selector(openSetup)))
        menu.addItem(item("Settings…", #selector(openSettings), key: ","))
        menu.addItem(.separator())
        menu.addItem(item("Quit mac-workspaces", #selector(quit), key: "q"))
    }

    private func disabled(_ title: String) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.isEnabled = false
        return item
    }

    private func item(_ title: String, _ selector: Selector, key: String = "") -> NSMenuItem {
        let item = NSMenuItem(title: title, action: selector, keyEquivalent: key)
        item.target = self
        return item
    }

    private func actionItem(_ action: Action, title: String) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: #selector(performAction(_:)), keyEquivalent: "")
        item.target = self
        item.representedObject = action.id
        if action != .launchTerminal { item.isEnabled = model.aerospaceReachable }
        if let s = model.settings.shortcut(for: action) { applyShortcutHint(s, to: item) }
        return item
    }

    /// Shows the shortcut next to a menu item. These are display-only: AeroSpace owns the
    /// global binding, and an open menu would otherwise handle the key a second time.
    private func applyShortcutHint(_ shortcut: Shortcut, to item: NSMenuItem) {
        item.toolTip = shortcut.spokenLabel
        item.title += "    " + shortcut.symbolLabel
    }

    @objc private func switchWorkspace(_ sender: NSMenuItem) {
        if let name = sender.representedObject as? String { model.switchWorkspace(name) }
    }

    @objc private func performAction(_ sender: NSMenuItem) {
        if let id = sender.representedObject as? String, let action = Action(id: id) { model.perform(action) }
    }

    @objc private func togglePause() { model.togglePause() }
    @objc private func openSetup() { showSetup() }
    @objc private func openSettings() { showSettings() }
    @objc private func openReference() { showReference() }
    @objc private func quit() { NSApp.terminate(nil) }

    // MARK: Windows

    func showSetup() {
        show("setup", title: "mac-workspaces Setup", size: NSSize(width: 640, height: 640)) {
            SetupView(onOpenSettings: { [weak self] in self?.showSettings() },
                      onClose: { [weak self] in self?.windows["setup"]?.close() })
        }
    }

    func showSettings() {
        show("settings", title: "mac-workspaces Settings", size: NSSize(width: 720, height: 620)) { SettingsView() }
    }

    func showReference() {
        show("reference", title: "Shortcut Reference", size: NSSize(width: 460, height: 620)) { ShortcutReferenceView() }
    }

    private func show<V: View>(_ key: String, title: String, size: NSSize, content: () -> V) {
        model.refreshStatus()
        if let window = windows[key] {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        let host = NSHostingController(rootView: content().environmentObject(model))
        let window = NSWindow(contentViewController: host)
        window.title = title
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
        window.setContentSize(size)
        window.isReleasedWhenClosed = false
        window.center()
        windows[key] = window
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}

/// Menu bar title: occupied workspaces, with the focused one emphasized.
enum StatusTitle {
    @MainActor
    static func make(model: AppModel) -> NSAttributedString {
        let font = NSFont.monospacedDigitSystemFont(ofSize: NSFont.systemFontSize, weight: .regular)
        let bold = NSFont.monospacedDigitSystemFont(ofSize: NSFont.systemFontSize, weight: .bold)
        guard model.aerospaceReachable else {
            return NSAttributedString(string: "⚠︎ WS", attributes: [.font: font])
        }
        let result = NSMutableAttributedString()
        if model.isPaused {
            result.append(NSAttributedString(string: "⏸ ", attributes: [.font: font]))
        }
        let snap = model.snapshot
        let visible = Action.workspaceNumbers.map(String.init).filter { snap.occupied.contains($0) || snap.focused == $0 }
        for (i, ws) in visible.enumerated() {
            if i > 0 { result.append(NSAttributedString(string: " ", attributes: [.font: font])) }
            if ws == snap.focused {
                result.append(NSAttributedString(string: "[\(ws)]", attributes: [.font: bold, .foregroundColor: NSColor.labelColor]))
            } else {
                result.append(NSAttributedString(string: ws, attributes: [.font: font, .foregroundColor: NSColor.secondaryLabelColor]))
            }
        }
        if let focused = snap.focused, let name = model.settings.displayName(forWorkspace: focused) {
            result.append(NSAttributedString(string: " \(name)", attributes: [.font: font]))
        }
        if result.length == 0 { result.append(NSAttributedString(string: "WS", attributes: [.font: font])) }
        return result
    }
}

/// Lightweight feedback without requiring notification permission: a transient panel.
enum Notifier {
    @MainActor private static var panel: NSPanel?
    @MainActor private static var hideWork: DispatchWorkItem?

    @MainActor
    static func show(_ message: String) {
        let label = NSTextField(wrappingLabelWithString: message)
        label.font = .systemFont(ofSize: 12)
        label.preferredMaxLayoutWidth = 360
        let size = label.fittingSize
        let frame = NSRect(x: 0, y: 0, width: min(size.width, 360) + 24, height: size.height + 16)
        let p = panel ?? NSPanel(contentRect: frame, styleMask: [.nonactivatingPanel, .hudWindow, .utilityWindow, .titled], backing: .buffered, defer: false)
        p.title = "mac-workspaces"
        p.level = .statusBar
        p.isFloatingPanel = true
        p.hidesOnDeactivate = false
        p.setContentSize(frame.size)
        label.frame = frame.insetBy(dx: 12, dy: 8)
        let container = NSView(frame: frame)
        container.addSubview(label)
        p.contentView = container
        if let screen = NSScreen.main {
            let v = screen.visibleFrame
            p.setFrameTopLeftPoint(NSPoint(x: v.maxX - p.frame.width - 12, y: v.maxY - 12))
        }
        p.orderFrontRegardless()
        panel = p
        hideWork?.cancel()
        let work = DispatchWorkItem { panel?.orderOut(nil) }
        hideWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 6, execute: work)
    }
}
