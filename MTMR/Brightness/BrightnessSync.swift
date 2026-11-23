import Cocoa

/// Controls external DDC monitors and, while syncing, makes them follow the built-in display.
///
/// Each monitor keeps an offset to the built-in level: syncing sets it to `built-in + offset`,
/// and moving the monitor's own slider changes the offset. Touch Bar slider, brightness keys
/// and auto-brightness all change the built-in level, and a poll picks up every change.
/// DDC writes run on a serial queue and are coalesced, so a fast slider drag sends only the
/// latest value.
final class BrightnessSync {
    static let shared = BrightnessSync()

    struct External {
        /// Short name; also the key for the saved offset.
        let name: String
        /// Name as macOS shows it.
        let fullName: String
        /// Whether the monitor answered over DDC.
        let replied: Bool
        /// Last level sent, 0…1.
        fileprivate(set) var level: Float
        fileprivate(set) var offset: Float
    }

    /// Called on the main queue after the display list was refreshed.
    var onDisplaysChanged: (() -> Void)?
    /// External monitors, in the same order as the DDC queue's `displays`. Main queue only.
    private(set) var externals: [External] = []

    private let ddcQueue = DispatchQueue(label: "com.toxblh.mtmr.ddc", qos: .userInitiated)
    private var displays: [ExternalDisplay] = [] // ddcQueue only
    private let lock = NSLock()
    private var pendingLevels: [Int: Float] = [:] // guarded by lock
    private var flushScheduled = false // guarded by lock

    private var started = false
    private var timer: Timer?
    private var builtInID: CGDirectDisplayID?
    private var lastLevel: Float?
    private var observers: [(NotificationCenter, NSObjectProtocol)] = []

    var isSyncing: Bool { timer != nil }

    /// Starts watching for monitors. Syncing is switched separately with `setSyncing(_:)`.
    func start() {
        guard !started else { return }
        started = true

        let refresh: (Notification) -> Void = { [weak self] _ in self?.refreshDisplays() }
        let wakeRefresh: (Notification) -> Void = { [weak self] _ in
            // Monitors come back a few seconds after wake and may have reset their brightness.
            DispatchQueue.main.asyncAfter(deadline: .now() + 3) { self?.refreshDisplays() }
        }
        let workspace = NSWorkspace.shared.notificationCenter
        observers = [
            (.default, NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main, using: refresh)),
            (workspace, workspace.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main, using: wakeRefresh)),
            (workspace, workspace.addObserver(forName: NSWorkspace.screensDidWakeNotification, object: nil, queue: .main, using: wakeRefresh)),
        ]
        refreshDisplays()
    }

    func setSyncing(_ on: Bool) {
        guard on != isSyncing else { return }
        if on {
            let timer = Timer(timeInterval: 0.1, repeats: true) { [weak self] _ in self?.poll() }
            RunLoop.main.add(timer, forMode: .common)
            self.timer = timer
            lastLevel = nil
            poll()
        } else {
            timer?.invalidate()
            timer = nil
        }
    }

    /// Pushes the current built-in level now instead of waiting for the next poll.
    func syncNow() {
        poll()
    }

    /// Sets one monitor directly and remembers its offset to the built-in display.
    func setLevel(_ level: Float, ofExternalAt index: Int) {
        guard externals.indices.contains(index) else { return }
        let level = Self.clamp(level)
        externals[index].level = level
        if let builtIn = builtInID.flatMap(BuiltInDisplay.brightness(of:)) {
            externals[index].offset = level - builtIn
            var saved = AppSettings.externalBrightnessOffsets
            saved[externals[index].name] = Double(externals[index].offset)
            AppSettings.externalBrightnessOffsets = saved
        }
        enqueue([index: level])
    }

    /// Re-enumerates external displays, then sends them the current level.
    func refreshDisplays() {
        builtInID = BuiltInDisplay.displayID
        ddcQueue.async { [weak self] in
            let found = ExternalDisplay.all()
            found.forEach { $0.probe() }
            self?.displays = found
            let probed = found.map { (replied: $0.replied, level: $0.initialLevel) }
            NSLog("MTMR: %d external display(s), %d answering over DDC", found.count, probed.filter(\.replied).count)
            DispatchQueue.main.async { self?.didFind(probed) }
        }
    }

    private func didFind(_ probed: [(replied: Bool, level: Float?)]) {
        // IORegistry and NSScreen order are matched by position. Exact for one monitor; with
        // several, names can be swapped.
        let screenNames = Self.externalScreenNames()
        let fullNames = screenNames.count == probed.count
            ? screenNames
            : probed.indices.map { "Display \($0 + 1)" }
        let saved = AppSettings.externalBrightnessOffsets
        let builtIn = builtInID.flatMap(BuiltInDisplay.brightness(of:))
        externals = zip(fullNames, probed).map { fullName, display in
            let name = DisplayName.short(fullName)
            let offset = Float(saved[name] ?? 0)
            let level = display.level ?? Self.clamp((builtIn ?? 0.5) + offset)
            return External(name: name, fullName: fullName, replied: display.replied, level: level, offset: offset)
        }
        lastLevel = nil // forces a send on the next poll
        poll()
        onDisplaysChanged?()
    }

    private func poll() {
        guard isSyncing, let display = builtInID, let level = BuiltInDisplay.brightness(of: display) else { return }
        if let last = lastLevel, abs(last - level) < 0.001 { return }
        lastLevel = level
        var targets: [Int: Float] = [:]
        for index in externals.indices {
            externals[index].level = Self.clamp(level + externals[index].offset)
            targets[index] = externals[index].level
        }
        enqueue(targets)
    }

    private func enqueue(_ levels: [Int: Float]) {
        guard !levels.isEmpty else { return }
        lock.lock()
        pendingLevels.merge(levels) { _, new in new }
        let needsFlush = !flushScheduled
        flushScheduled = true
        lock.unlock()
        if needsFlush {
            ddcQueue.async { [weak self] in self?.flush() }
        }
    }

    private func flush() {
        while true {
            lock.lock()
            let levels = pendingLevels
            pendingLevels = [:]
            if levels.isEmpty { flushScheduled = false }
            lock.unlock()
            if levels.isEmpty { return }
            for (index, level) in levels where displays.indices.contains(index) {
                displays[index].setBrightness(level: level)
            }
        }
    }

    private static func clamp(_ level: Float) -> Float {
        min(max(level, 0), 1)
    }

    private static func externalScreenNames() -> [String] {
        NSScreen.screens.compactMap { screen in
            guard let id = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID,
                  CGDisplayIsBuiltin(id) == 0 else { return nil }
            return screen.localizedName
        }
    }
}
