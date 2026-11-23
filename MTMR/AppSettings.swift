import Foundation

enum AppSettings {
    @UserDefault(key: "com.toxblh.mtmr.settings.showControlStrip", defaultValue: false)
    static var showControlStrip: Bool

    @UserDefault(key: "com.toxblh.mtmr.settings.syncExternalBrightness", defaultValue: true)
    static var syncExternalBrightness: Bool

    /// Per monitor (by short name): brightness offset to the built-in display, -1…1.
    @UserDefault(key: "com.toxblh.mtmr.settings.externalBrightnessOffsets", defaultValue: [:])
    static var externalBrightnessOffsets: [String: Double]
}

@propertyWrapper
struct UserDefault<T> {
    let key: String
    let defaultValue: T

    var wrappedValue: T {
        get { UserDefaults.standard.object(forKey: key) as? T ?? defaultValue }
        set { UserDefaults.standard.set(newValue, forKey: key) }
    }
}
