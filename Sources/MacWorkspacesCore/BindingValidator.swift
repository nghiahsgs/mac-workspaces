import Foundation

public struct BindingIssue: Hashable, Sendable, CustomStringConvertible {
    public enum Severity: String, Sendable { case error, warning }

    public enum Kind: Hashable, Sendable {
        /// Two product actions share one shortcut.
        case duplicate(Shortcut, [Action])
        /// The key name is not one AeroSpace understands.
        case invalidKey(Action, String)
        /// No modifier: the binding would swallow ordinary typing.
        case noModifier(Action, Shortcut)
        /// Overrides a widely used macOS / app shortcut.
        case systemShortcut(Action, Shortcut, String)
        /// Option (+ Shift) + a character key types special characters on many layouts.
        /// Reported once for all affected actions to keep the list readable.
        case optionCharacter([Action])
    }

    public let kind: Kind

    public var severity: Severity {
        switch kind {
        case .duplicate, .invalidKey, .noModifier: return .error
        case .systemShortcut, .optionCharacter: return .warning
        }
    }

    public var actions: [Action] {
        switch kind {
        case .duplicate(_, let actions): return actions
        case .optionCharacter(let actions): return actions
        case .invalidKey(let a, _), .noModifier(let a, _), .systemShortcut(let a, _, _):
            return [a]
        }
    }

    public var description: String {
        switch kind {
        case .duplicate(let s, let actions):
            return "\(s.symbolLabel) is assigned to more than one action: " + actions.map(\.title).joined(separator: ", ")
        case .invalidKey(let a, let key):
            return "\"\(key)\" is not a key AeroSpace recognizes (\(a.title))."
        case .noModifier(let a, let s):
            return "\(s.symbolLabel) has no modifier and would block normal typing (\(a.title))."
        case .systemShortcut(let a, let s, let usual):
            return "\(s.symbolLabel) normally means \"\(usual)\" in macOS or many apps; binding it to \(a.title) overrides that everywhere."
        case .optionCharacter(let actions):
            return "\(actions.count) Option-key bindings (e.g. ⌥H, ⌥1) type special characters on some keyboard layouts; while bound, those characters cannot be typed. Change them if you rely on Option for character entry."
        }
    }
}

public enum BindingValidator {
    /// Shortcuts that macOS or most apps already use. Overriding them is allowed but warned.
    public static let knownSystemShortcuts: [String: String] = [
        "cmd-enter": "Send / confirm in some apps",
        "cmd-q": "Quit",
        "cmd-w": "Close window",
        "cmd-h": "Hide app",
        "cmd-m": "Minimize",
        "cmd-tab": "App switcher",
        "cmd-space": "Spotlight",
        "cmd-c": "Copy",
        "cmd-v": "Paste",
        "cmd-x": "Cut",
        "cmd-z": "Undo",
        "cmd-a": "Select all",
        "cmd-s": "Save",
        "cmd-n": "New window",
        "cmd-t": "New tab",
        "cmd-f": "Find",
        "cmd-backtick": "Cycle windows",
        "cmd-comma": "Settings",
        "ctrl-space": "Input source",
        "ctrl-up": "Mission Control",
        "ctrl-down": "App windows",
        "ctrl-left": "Previous Space",
        "ctrl-right": "Next Space",
    ]

    public static func validate(_ settings: Settings) -> [BindingIssue] {
        var issues: [BindingIssue] = []
        var byShortcut: [Shortcut: [Action]] = [:]
        var optionCharacterActions: [Action] = []

        for (action, shortcut) in settings.effectiveBindings {
            guard let shortcut else { continue }
            byShortcut[shortcut, default: []].append(action)

            if !KeyNames.isValid(shortcut.key) {
                issues.append(BindingIssue(kind: .invalidKey(action, shortcut.key)))
                continue
            }
            let isFunctionLike = shortcut.key.hasPrefix("f") && shortcut.key.count > 1 && shortcut.key.dropFirst().allSatisfy(\.isNumber)
            if shortcut.modifiers.isEmpty && !isFunctionLike {
                issues.append(BindingIssue(kind: .noModifier(action, shortcut)))
            }
            if let usual = knownSystemShortcuts[shortcut.notation] {
                issues.append(BindingIssue(kind: .systemShortcut(action, shortcut, usual)))
            }
            let optionOnly = shortcut.modifiers == [.alt] || shortcut.modifiers == [.alt, .shift]
            if optionOnly && isCharacterKey(shortcut.key) {
                optionCharacterActions.append(action)
            }
        }

        if !optionCharacterActions.isEmpty {
            issues.append(BindingIssue(kind: .optionCharacter(optionCharacterActions)))
        }
        for (shortcut, actions) in byShortcut where actions.count > 1 {
            issues.append(BindingIssue(kind: .duplicate(shortcut, actions)))
        }
        return issues.sorted { lhs, rhs in
            if lhs.severity != rhs.severity { return lhs.severity == .error }
            return lhs.description < rhs.description
        }
    }

    public static func errors(in settings: Settings) -> [BindingIssue] {
        validate(settings).filter { $0.severity == .error }
    }

    static func isCharacterKey(_ key: String) -> Bool {
        KeyNames.letters.contains(key) || KeyNames.digits.contains(key) || [
            "minus", "equal", "period", "comma", "slash", "backslash", "quote", "semicolon",
            "backtick", "leftSquareBracket", "rightSquareBracket", "sectionSign",
        ].contains(key)
    }
}
