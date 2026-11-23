import Cocoa
import ServiceManagement

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    private var presetWatcher: DispatchSourceFileSystemObject?

    func applicationDidFinishLaunching(_: Notification) {
        // Posting key events (esc, media keys) needs Accessibility access.
        AXIsProcessTrustedWithOptions([kAXTrustedCheckOptionPrompt.takeRetainedValue() as String: true] as CFDictionary)

        statusItem.button?.image = #imageLiteral(resourceName: "StatusImage")
        BrightnessSync.shared.onDisplaysChanged = { [weak self] in
            self?.createMenu()
            TouchBarController.shared.displaysChanged()
        }
        createMenu()

        TouchBarController.shared.setupControlStripPresence()
        TouchBarController.shared.reloadStandardConfig()
        watchPreset()

        BrightnessSync.shared.start()
        BrightnessSync.shared.setSyncing(AppSettings.syncExternalBrightness)
    }

    private func createMenu() {
        let menu = NSMenu()
        menu.addItem(withTitle: "Edit preset…", action: #selector(openPreset), keyEquivalent: ",")
        menu.addItem(.separator())

        let sync = NSMenuItem(title: "Sync brightness to external display", action: #selector(toggleBrightnessSync), keyEquivalent: "")
        sync.state = AppSettings.syncExternalBrightness ? .on : .off
        menu.addItem(sync)
        let externals = BrightnessSync.shared.externals
        let info = NSMenuItem(title: "  External: \(externals.count) found, \(externals.filter(\.replied).count) answering over DDC", action: nil, keyEquivalent: "")
        info.isEnabled = false
        menu.addItem(info)
        menu.addItem(withTitle: "  Rescan displays", action: #selector(rescanDisplays), keyEquivalent: "")

        let hideControlStrip = NSMenuItem(title: "Hide Control Strip", action: #selector(toggleControlStrip), keyEquivalent: "")
        hideControlStrip.state = AppSettings.showControlStrip ? .off : .on
        menu.addItem(hideControlStrip)

        if #available(macOS 13.0, *) {
            let login = NSMenuItem(title: "Start at login", action: #selector(toggleStartAtLogin), keyEquivalent: "")
            login.state = SMAppService.mainApp.status == .enabled ? .on : .off
            menu.addItem(login)
        }

        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        menu.items.forEach { if $0.action != #selector(NSApplication.terminate(_:)) { $0.target = self } }
        statusItem.menu = menu
    }

    @objc private func openPreset() {
        NSWorkspace.shared.open(URL(fileURLWithPath: standardConfigPath))
    }

    @objc private func toggleBrightnessSync() {
        AppSettings.syncExternalBrightness.toggle()
        BrightnessSync.shared.setSyncing(AppSettings.syncExternalBrightness)
        createMenu()
    }

    @objc private func rescanDisplays() {
        BrightnessSync.shared.refreshDisplays()
    }

    @objc private func toggleControlStrip() {
        AppSettings.showControlStrip.toggle()
        TouchBarController.shared.resetControlStrip()
        createMenu()
    }

    @available(macOS 13.0, *)
    @objc private func toggleStartAtLogin() {
        do {
            if SMAppService.mainApp.status == .enabled {
                try SMAppService.mainApp.unregister()
            } else {
                try SMAppService.mainApp.register()
            }
        } catch {
            NSLog("MTMR: cannot change login item: %@", String(describing: error))
        }
        createMenu()
    }

    /// Reloads the Touch Bar whenever `items.json` is saved.
    private func watchPreset() {
        let fd = open(standardConfigPath, O_EVTONLY)
        guard fd >= 0 else { return }
        let source = DispatchSource.makeFileSystemObjectSource(fileDescriptor: fd, eventMask: [.write, .delete, .rename], queue: .main)
        source.setEventHandler { [weak self, weak source] in
            guard let source = source else { return }
            if source.data.isDisjoint(with: [.delete, .rename]) {
                TouchBarController.shared.reloadPreset(path: standardConfigPath)
                return
            }
            // Editors that save atomically replace the file: wait for the new one, then watch it.
            source.cancel()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                TouchBarController.shared.reloadPreset(path: standardConfigPath)
                self?.watchPreset()
            }
        }
        source.setCancelHandler { close(fd) }
        source.resume()
        presetWatcher = source
    }
}
