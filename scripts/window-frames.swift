// Prints "<CGWindowID> <x> <y> <w> <h>" for on-screen windows of the given owner name.
// AeroSpace window ids are CGWindowIDs. Bounds do not require Screen Recording permission.
import CoreGraphics
import Foundation
let owner = CommandLine.arguments.dropFirst().first ?? "Terminal"
let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] ?? []
for w in list where (w[kCGWindowOwnerName as String] as? String) == owner && (w[kCGWindowLayer as String] as? Int) == 0 {
    guard let id = w[kCGWindowNumber as String] as? Int,
          let b = w[kCGWindowBounds as String] as? [String: CGFloat] else { continue }
    print(id, Int(b["X"] ?? 0), Int(b["Y"] ?? 0), Int(b["Width"] ?? 0), Int(b["Height"] ?? 0))
}
