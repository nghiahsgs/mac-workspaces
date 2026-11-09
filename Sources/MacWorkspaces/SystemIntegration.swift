import AppKit
import ServiceManagement

enum PermissionStatus: Equatable {
    case granted, denied, notDetermined, unknown(String)

    var label: String {
        switch self {
        case .granted: return "Allowed"
        case .denied: return "Denied"
        case .notDetermined: return "Not requested yet"
        case .unknown(let why): return why
        }
    }
}

enum Automation {
    /// Checks (and optionally requests) permission to send Apple Events to an app.
    /// The target must be running for macOS to answer.
    static func status(bundleID: String, ask: Bool) -> PermissionStatus {
        var address = AEAddressDesc()
        let created = bundleID.withCString { ptr in
            AECreateDesc(DescType(typeApplicationBundleID), ptr, strlen(ptr), &address)
        }
        guard created == noErr else { return .unknown("Could not check") }
        defer { AEDisposeDesc(&address) }
        let result = AEDeterminePermissionToAutomateTarget(&address, AEEventClass(typeWildCard), AEEventID(typeWildCard), ask)
        switch result {
        case noErr: return .granted
        case OSStatus(errAEEventNotPermitted): return .denied
        case OSStatus(errAEEventWouldRequireUserConsent): return .notDetermined
        case OSStatus(procNotFound): return .unknown("Open Terminal to check")
        default: return .unknown("Unknown (\(result))")
        }
    }
}

enum SystemSettings {
    static func openAccessibility() {
        open("x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")
    }

    static func openAutomation() {
        open("x-apple.systempreferences:com.apple.preference.security?Privacy_Automation")
    }

    private static func open(_ string: String) {
        if let url = URL(string: string) { NSWorkspace.shared.open(url) }
    }
}

enum LoginItem {
    static var isEnabled: Bool { SMAppService.mainApp.status == .enabled }

    static var statusDescription: String {
        switch SMAppService.mainApp.status {
        case .enabled: return "Enabled"
        case .notRegistered: return "Off"
        case .requiresApproval: return "Needs approval in System Settings › General › Login Items"
        case .notFound: return "Unavailable (move the app to /Applications)"
        @unknown default: return "Unknown"
        }
    }

    static func set(_ enabled: Bool) throws {
        if enabled { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
    }
}

enum AeroSpaceApp {
    static let bundleID = "bobko.aerospace"

    static var isInstalled: Bool {
        NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) != nil
    }

    static var isRunning: Bool {
        !NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).isEmpty
    }

    static func launch() {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else { return }
        NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
    }

    static let installCommand = "brew install --cask nikitabobko/tap/aerospace"
    static let guideURL = URL(string: "https://nikitabobko.github.io/AeroSpace/guide")!
}
