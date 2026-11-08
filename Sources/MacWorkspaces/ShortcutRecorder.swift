import AppKit
import SwiftUI
import MacWorkspacesCore

/// Click, then press a key combination. Esc cancels. Records AeroSpace key names.
struct ShortcutRecorder: View {
    @Binding var shortcut: Shortcut?
    @State private var recording = false
    @State private var monitor: Any?

    var body: some View {
        Button {
            recording ? stop() : start()
        } label: {
            Text(recording ? "Press keys…" : (shortcut?.symbolLabel ?? "None"))
                .font(.system(.body, design: .monospaced))
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.bordered)
        .tint(recording ? .accentColor : nil)
        .onDisappear { stop() }
    }

    private func start() {
        recording = true
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            if event.keyCode == 0x35 && event.modifierFlags.intersection([.command, .option, .control, .shift]).isEmpty {
                stop()  // Esc alone cancels
                return nil
            }
            if let recorded = ShortcutRecorder.shortcut(from: event) {
                shortcut = recorded
                stop()
            } else {
                NSSound.beep()
            }
            return nil
        }
    }

    private func stop() {
        recording = false
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
    }

    static func shortcut(from event: NSEvent) -> Shortcut? {
        guard let key = KeyNames.keyName(forVirtualKeyCode: event.keyCode) else { return nil }
        var mods = Set<Modifier>()
        let flags = event.modifierFlags
        if flags.contains(.command) { mods.insert(.cmd) }
        if flags.contains(.option) { mods.insert(.alt) }
        if flags.contains(.control) { mods.insert(.ctrl) }
        if flags.contains(.shift) { mods.insert(.shift) }
        return Shortcut(mods, key)
    }
}
