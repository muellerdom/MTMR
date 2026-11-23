import CoreGraphics

/// Brightness of the MacBook's built-in panel, via the private DisplayServices framework.
enum BuiltInDisplay {
    /// The built-in display, or nil when the lid is closed.
    static var displayID: CGDirectDisplayID? {
        var count: UInt32 = 0
        guard CGGetOnlineDisplayList(0, nil, &count) == .success, count > 0 else { return nil }
        var ids = [CGDirectDisplayID](repeating: 0, count: Int(count))
        guard CGGetOnlineDisplayList(count, &ids, &count) == .success else { return nil }
        return ids.prefix(Int(count)).first { CGDisplayIsBuiltin($0) != 0 }
    }

    /// Current level, 0…1.
    static func brightness(of display: CGDirectDisplayID) -> Float? {
        var level: Float = 0
        return DisplayServicesGetBrightness(display, &level) == 0 ? level : nil
    }

    static var brightness: Float? {
        displayID.flatMap(brightness(of:))
    }

    static func setBrightness(_ level: Float) {
        guard let display = displayID else { return }
        DisplayServicesSetBrightness(display, min(max(level, 0), 1))
    }
}
