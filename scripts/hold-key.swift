// Simulates holding ⌘Return: key-down, auto-repeat key-downs every 30 ms, key-up.
// Posted at the HID tap so it looks like hardware input (needs Accessibility for the host app).
// Usage: hold-key <seconds> [press]   ("press" = a single tap instead of a hold)
import CoreGraphics
import Foundation
import ApplicationServices
let seconds = Double(CommandLine.arguments.dropFirst().first ?? "1.5") ?? 1.5
let tapOnly = CommandLine.arguments.contains("press")
let src = CGEventSource(stateID: .hidSystemState)
let ret: CGKeyCode = 0x24, cmd: CGKeyCode = 0x37
func post(_ key: CGKeyCode, _ down: Bool, repeatFlag: Bool = false) {
    let e = CGEvent(keyboardEventSource: src, virtualKey: key, keyDown: down)!
    if key == ret { e.flags = .maskCommand }
    if repeatFlag { e.setIntegerValueField(.keyboardEventAutorepeat, value: 1) }
    e.post(tap: .cghidEventTap)
}
print("trusted for posting:", AXIsProcessTrusted())
post(cmd, true); usleep(20_000)
post(ret, true)
if !tapOnly {
    usleep(500_000)  // initial repeat delay
    var t = 0.5
    while t < seconds { post(ret, true, repeatFlag: true); usleep(30_000); t += 0.03 }
    print("keyState while held:", CGEventSource.keyState(.combinedSessionState, key: ret))
} else { usleep(60_000) }
post(ret, false); usleep(20_000); post(cmd, false)
print("keyState after release:", CGEventSource.keyState(.combinedSessionState, key: ret))
