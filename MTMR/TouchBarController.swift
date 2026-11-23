import Cocoa

let appSupportDirectory = NSSearchPathForDirectoriesInDomains(.applicationSupportDirectory, .userDomainMask, true).first!.appending("/MTMR")
let standardConfigPath = appSupportDirectory.appending("/items.json")

extension NSTouchBarItem.Identifier {
    static let controlStripItem = NSTouchBarItem.Identifier("com.toxblh.mtmr.controlStrip")
    static let brightnessStripItem = NSTouchBarItem.Identifier("com.toxblh.mtmr.controlStrip.brightness")
}

final class TouchBarController: NSObject, NSTouchBarDelegate {
    static let shared = TouchBarController()

    private var touchBar = NSTouchBar()
    /// The bar built from the preset.
    private var mainRoot: RootItem?
    /// Keep the items alive: their views only hold weak references back to them.
    private var items: [NSTouchBarItem] = []
    /// The expanded brightness sliders, while shown.
    private var overlayItems: [NSTouchBarItem] = []
    private var isOverlayShown: Bool { !overlayItems.isEmpty }
    /// Whether closing the brightness sliders should leave MTMR's bar minimized, because it
    /// was not showing when they were opened from the Control Strip.
    private var minimizeAfterOverlay = false
    /// Notices when the system's close button dismissed the sliders.
    private var overlayWatcher: Timer?

    override private init() {
        super.init()
        // Other apps can take over the Touch Bar; bring ours back when the front app changes.
        NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(presentTouchBar), name: NSWorkspace.didActivateApplicationNotification, object: nil)
    }

    func setupControlStripPresence() {
        DFRSystemModalShowsCloseBoxWhenFrontMost(false)
        let item = NSCustomTouchBarItem(identifier: .controlStripItem)
        item.view = NSButton(image: #imageLiteral(resourceName: "StatusImage"), target: self, action: #selector(presentTouchBar))
        NSTouchBarItem.addSystemTrayItem(item)
        DFRElementSetControlStripPresenceForIdentifier(.controlStripItem, true)

        // Sun button in the Control Strip, in place of Apple's brightness button.
        let brightness = NSCustomTouchBarItem(identifier: .brightnessStripItem)
        brightness.view = NSButton(image: DisplayIcons.sun, target: self, action: #selector(toggleBrightnessOverlay))
        NSTouchBarItem.addSystemTrayItem(brightness)
        DFRElementSetControlStripPresenceForIdentifier(.brightnessStripItem, true)
    }

    func reloadStandardConfig() {
        if !FileManager.default.fileExists(atPath: standardConfigPath),
           let defaultPreset = Bundle.main.path(forResource: "defaultPreset", ofType: "json") {
            try? FileManager.default.createDirectory(atPath: appSupportDirectory, withIntermediateDirectories: true)
            try? FileManager.default.copyItem(atPath: defaultPreset, toPath: standardConfigPath)
        }
        reloadPreset(path: standardConfigPath)
    }

    func reloadPreset(path: String) {
        let definitions: [BarItemDefinition]
        do {
            let data = try Data(contentsOf: URL(fileURLWithPath: path))
            definitions = try BarItemDefinition.parsePreset(data)
        } catch {
            NSLog("MTMR: cannot load preset %@: %@", path, String(describing: error))
            definitions = [BarItemDefinition(type: .unsupported("bad preset"))]
        }
        build(definitions)
    }

    private func build(_ definitions: [BarItemDefinition]) {
        NSTouchBar.minimizeSystemModalTouchBar(touchBar)

        let built = definitions.map { ($0, makeItem($0)) }
        items = built.map(\.1)
        let column = { (align: Align) in built.filter { $0.0.align == align }.map(\.1) }

        mainRoot = RootItem(identifier: Self.newIdentifier("root"), left: column(.left), center: column(.center), right: column(.right))
        endOverlay()
        show(mainRoot.map { [$0.identifier] } ?? [])
    }

    @objc func toggleBrightnessOverlay() {
        if isOverlayShown {
            dismissBrightnessOverlay()
        } else {
            showBrightnessOverlay()
        }
    }

    /// Replaces the bar with one brightness slider per display, like Apple's expanded
    /// brightness control. With more displays than fit, the row scrolls horizontally.
    /// The system's close button or another tap on the sun closes it.
    func showBrightnessOverlay() {
        let sync = BrightnessSync.shared
        if !isOverlayShown {
            minimizeAfterOverlay = !touchBar.isVisible
            // Only when opening: a rescan ends in displaysChanged(), which calls this again.
            if sync.externals.isEmpty, NSScreen.screens.count > 1 {
                sync.refreshDisplays()
            }
        }

        let builtIn = LabeledSliderItem(identifier: Self.newIdentifier("slider"), label: nil, icons: .builtIn,
                                        read: { BuiltInDisplay.brightness },
                                        write: { level in
                                            BuiltInDisplay.setBrightness(level)
                                            BrightnessSync.shared.syncNow()
                                        })
        let externals = sync.externals.indices.map { index in
            LabeledSliderItem(identifier: Self.newIdentifier("slider"), label: sync.externals[index].fullName, icons: .external,
                              read: { sync.externals.indices.contains(index) ? sync.externals[index].level : nil },
                              write: { sync.setLevel($0, ofExternalAt: index) })
        }
        let sliders = [builtIn] + externals
        let row = ScrollingRowItem(identifier: Self.newIdentifier("sliders"), items: sliders, spacing: 12,
                                   maxWidth: Self.overlayWidth)
        sliders.forEach { $0.onResize = { [weak row] in row?.relayout() } }
        overlayItems = [row] + sliders
        show([row.identifier])
        watchOverlay()
    }

    /// Rebuilds the brightness sliders when a monitor was connected or removed.
    func displaysChanged() {
        if isOverlayShown {
            showBrightnessOverlay()
        }
    }

    /// Room for the slider row, kept on the small side: if it is too small the row scrolls,
    /// if it were too large the end of the row would be cut off. Touch Bar of the 13" models
    /// with a physical Esc key (1004 pt) minus the system close button and, when shown, the
    /// collapsed Control Strip.
    private static var overlayWidth: CGFloat {
        AppSettings.showControlStrip ? 560 : 860
    }

    func dismissBrightnessOverlay() {
        let present = !minimizeAfterOverlay
        endOverlay()
        show(mainRoot.map { [$0.identifier] } ?? [], present: present)
    }

    private func endOverlay() {
        overlayWatcher?.invalidate()
        overlayWatcher = nil
        overlayItems = []
        minimizeAfterOverlay = false
    }

    /// Once the sliders were on screen and then disappear, the system's close button (or another
    /// app) dismissed them: go back to the normal bar so the next presentation shows it.
    private func watchOverlay() {
        overlayWatcher?.invalidate()
        var seenVisible = false
        let timer = Timer(timeInterval: 0.3, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            if self.touchBar.isVisible {
                seenVisible = true
            } else if seenVisible {
                let present = !self.minimizeAfterOverlay
                self.endOverlay()
                self.show(self.mainRoot.map { [$0.identifier] } ?? [], present: present)
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        overlayWatcher = timer
    }

    private func show(_ identifiers: [NSTouchBarItem.Identifier], present: Bool = true) {
        NSTouchBar.minimizeSystemModalTouchBar(touchBar)
        touchBar = NSTouchBar()
        touchBar.delegate = self
        touchBar.defaultItemIdentifiers = identifiers
        if present {
            presentTouchBar()
        }
    }

    private static func newIdentifier(_ kind: String) -> NSTouchBarItem.Identifier {
        NSTouchBarItem.Identifier("com.toxblh.mtmr.\(kind).\(UUID().uuidString)")
    }

    @objc func presentTouchBar() {
        if AppSettings.showControlStrip {
            NSTouchBar.presentSystemModalTouchBar(touchBar, systemTrayItemIdentifier: .controlStripItem)
        } else {
            NSTouchBar.presentSystemModalTouchBar(touchBar, placement: 1, systemTrayItemIdentifier: .controlStripItem)
        }
    }

    func resetControlStrip() {
        NSTouchBar.minimizeSystemModalTouchBar(touchBar)
        presentTouchBar()
    }

    func touchBar(_: NSTouchBar, makeItemForIdentifier identifier: NSTouchBarItem.Identifier) -> NSTouchBarItem? {
        if identifier == mainRoot?.identifier {
            return mainRoot
        }
        return overlayItems.first { $0.identifier == identifier }
    }

    private func makeItem(_ definition: BarItemDefinition) -> NSTouchBarItem {
        let identifier = Self.newIdentifier("item")
        let item: NSCustomTouchBarItem

        func key(_ code: Int32, _ image: NSImage?) -> ButtonItem {
            ButtonItem(identifier: identifier, image: image) { HIDPostAuxKey(code) }
        }

        switch definition.type {
        case .escape:
            item = ButtonItem(identifier: identifier, title: "esc") { GenericKeyPress(keyCode: 53).send() }
        case .brightnessDown:
            item = key(NX_KEYTYPE_BRIGHTNESS_DOWN, #imageLiteral(resourceName: "brightnessDown"))
        case .brightnessUp:
            item = key(NX_KEYTYPE_BRIGHTNESS_UP, #imageLiteral(resourceName: "brightnessUp"))
        case .brightness:
            item = ButtonItem(identifier: identifier, image: DisplayIcons.sun) { [weak self] in
                self?.toggleBrightnessOverlay()
            }
        case .volumeDown:
            item = key(NX_KEYTYPE_SOUND_DOWN, NSImage(named: NSImage.touchBarVolumeDownTemplateName))
        case .volumeUp:
            item = key(NX_KEYTYPE_SOUND_UP, NSImage(named: NSImage.touchBarVolumeUpTemplateName))
        case .mute:
            item = key(NX_KEYTYPE_MUTE, NSImage(named: NSImage.touchBarAudioOutputMuteTemplateName))
        case .play:
            item = key(NX_KEYTYPE_PLAY, NSImage(named: NSImage.touchBarPlayPauseTemplateName))
        case let .timeButton(formatTemplate, timeZone, locale):
            item = TimeItem(identifier: identifier, formatTemplate: formatTemplate, timeZone: timeZone, locale: locale)
        case let .unsupported(name):
            item = ButtonItem(identifier: identifier, title: name)
        }

        if let bordered = definition.bordered, let button = item as? ButtonItem {
            button.isBordered = bordered
        }
        if let width = definition.width {
            item.view.widthAnchor.constraint(equalToConstant: width).isActive = true
        }
        return item
    }
}
