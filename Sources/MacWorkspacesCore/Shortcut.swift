import Foundation

/// A keyboard modifier, using AeroSpace's notation.
public enum Modifier: String, Codable, CaseIterable, Comparable, Sendable {
    case cmd, alt, ctrl, shift

    /// AeroSpace writes modifiers in this canonical order: cmd-alt-ctrl-shift.
    var order: Int {
        switch self {
        case .cmd: return 0
        case .alt: return 1
        case .ctrl: return 2
        case .shift: return 3
        }
    }

    public static func < (lhs: Modifier, rhs: Modifier) -> Bool { lhs.order < rhs.order }

    public var symbol: String {
        switch self {
        case .cmd: return "⌘"
        case .alt: return "⌥"
        case .ctrl: return "⌃"
        case .shift: return "⇧"
        }
    }

    public var displayName: String {
        switch self {
        case .cmd: return "Command"
        case .alt: return "Option"
        case .ctrl: return "Control"
        case .shift: return "Shift"
        }
    }
}

/// Key names accepted by AeroSpace bindings (from AeroSpace's default-config.toml).
public enum KeyNames {
    public static let letters = (UnicodeScalar("a").value...UnicodeScalar("z").value)
        .map { String(UnicodeScalar($0)!) }
    public static let digits = (0...9).map(String.init)
    public static let special = [
        "minus", "equal", "period", "comma", "slash", "backslash", "quote", "semicolon",
        "backtick", "leftSquareBracket", "rightSquareBracket", "space", "enter", "esc",
        "backspace", "tab", "pageUp", "pageDown", "home", "end", "forwardDelete", "sectionSign",
    ]
    public static let arrows = ["left", "down", "up", "right"]
    public static let functionKeys = (1...20).map { "f\($0)" }
    public static let keypad = (0...9).map { "keypad\($0)" } + [
        "keypadClear", "keypadDecimalMark", "keypadDivide", "keypadEnter", "keypadEqual",
        "keypadMinus", "keypadMultiply", "keypadPlus",
    ]

    public static let all: [String] = letters + digits + special + arrows + functionKeys + keypad
    private static let allSet = Set(all)

    public static func isValid(_ key: String) -> Bool { allSet.contains(key) }

    /// Human-friendly label for a key name.
    public static func label(for key: String) -> String {
        switch key {
        case "enter": return "Return"
        case "minus": return "-"
        case "equal": return "="
        case "period": return "."
        case "comma": return ","
        case "slash": return "/"
        case "backslash": return "\\"
        case "quote": return "'"
        case "semicolon": return ";"
        case "backtick": return "`"
        case "leftSquareBracket": return "["
        case "rightSquareBracket": return "]"
        case "space": return "Space"
        case "esc": return "Esc"
        case "tab": return "Tab"
        case "backspace": return "Delete"
        case "left": return "←"
        case "right": return "→"
        case "up": return "↑"
        case "down": return "↓"
        default: return key.count == 1 ? key.uppercased() : key
        }
    }

    /// macOS virtual key codes (ANSI layout) for the keys most likely to be bound to the
    /// terminal launch action. Used to detect whether the launch key is still physically
    /// held so keyboard auto-repeat can be ignored.
    public static let virtualKeyCodes: [String: UInt16] = [
        "a": 0x00, "s": 0x01, "d": 0x02, "f": 0x03, "h": 0x04, "g": 0x05, "z": 0x06, "x": 0x07,
        "c": 0x08, "v": 0x09, "b": 0x0B, "q": 0x0C, "w": 0x0D, "e": 0x0E, "r": 0x0F, "y": 0x10,
        "t": 0x11, "1": 0x12, "2": 0x13, "3": 0x14, "4": 0x15, "6": 0x16, "5": 0x17, "equal": 0x18,
        "9": 0x19, "7": 0x1A, "minus": 0x1B, "8": 0x1C, "0": 0x1D, "rightSquareBracket": 0x1E,
        "o": 0x1F, "u": 0x20, "leftSquareBracket": 0x21, "i": 0x22, "p": 0x23, "enter": 0x24,
        "l": 0x25, "j": 0x26, "quote": 0x27, "k": 0x28, "semicolon": 0x29, "backslash": 0x2A,
        "comma": 0x2B, "slash": 0x2C, "n": 0x2D, "m": 0x2E, "period": 0x2F, "tab": 0x30,
        "space": 0x31, "backtick": 0x32, "backspace": 0x33, "esc": 0x35, "keypadEnter": 0x4C,
        "left": 0x7B, "right": 0x7C, "down": 0x7D, "up": 0x7E,
    ]
}

/// A key combination such as `cmd-enter` or `alt-shift-h`.
public struct Shortcut: Hashable, Codable, Sendable, CustomStringConvertible {
    public var modifiers: Set<Modifier>
    public var key: String

    public init(_ modifiers: Set<Modifier>, _ key: String) {
        self.modifiers = modifiers
        self.key = key
    }

    /// Parses AeroSpace notation, e.g. `alt-shift-h`. Returns nil if malformed.
    public init?(notation: String) {
        let parts = notation.trimmingCharacters(in: .whitespaces).split(separator: "-", omittingEmptySubsequences: false).map(String.init)
        guard let key = parts.last, !key.isEmpty else { return nil }
        var mods = Set<Modifier>()
        for part in parts.dropLast() {
            guard let m = Modifier(rawValue: part), !mods.contains(m) else { return nil }
            mods.insert(m)
        }
        self.init(mods, key)
    }

    /// AeroSpace notation with canonical modifier order.
    public var notation: String {
        (modifiers.sorted().map(\.rawValue) + [key]).joined(separator: "-")
    }

    /// e.g. "⌥⇧H"
    public var symbolLabel: String {
        modifiers.sorted().map(\.symbol).joined() + KeyNames.label(for: key)
    }

    /// e.g. "Option + Shift + H"
    public var spokenLabel: String {
        (modifiers.sorted().map(\.displayName) + [KeyNames.label(for: key)]).joined(separator: " + ")
    }

    public var description: String { notation }

    // Codable as a plain notation string, which keeps settings.json human-editable.
    public init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        let s = try c.decode(String.self)
        guard let parsed = Shortcut(notation: s) else {
            throw DecodingError.dataCorruptedError(in: c, debugDescription: "Invalid shortcut \(s)")
        }
        self = parsed
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        try c.encode(notation)
    }
}
