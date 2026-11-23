import Cocoa

/// A brightness slider drawn like Apple's expanded brightness control: one rounded grey
/// capsule with an optional label, a "darker" icon, the slider and a "brighter" icon.
/// Tapping an icon steps the value. Re-reads its value twice a second so that changes made
/// elsewhere (keys, auto-brightness, sync) show up.
final class LabeledSliderItem: NSCustomTouchBarItem {
    /// Same step as the brightness keys.
    private static let step: Float = 1.0 / 16
    static let capsuleColor = NSColor(white: 0.2, alpha: 1)

    private let slider = NSSlider(value: 0, minValue: 0, maxValue: 1, target: nil, action: nil)
    private let read: () -> Float?
    private let write: (Float) -> Void
    private var timer: Timer?
    private var labelButton: NSButton?
    private var labels: (short: String, full: String)?
    private var showsFullLabel = false
    /// Called after the label was expanded or collapsed and the item changed width.
    var onResize: (() -> Void)?

    /// `label`: shown abbreviated; tapping it toggles the full text.
    init(identifier: NSTouchBarItem.Identifier, label: String?, icons: DisplayIcons, sliderWidth: CGFloat = 160,
         read: @escaping () -> Float?, write: @escaping (Float) -> Void) {
        self.read = read
        self.write = write
        super.init(identifier: identifier)

        slider.cell = CompactSliderCell()
        slider.minValue = 0
        slider.maxValue = 1
        slider.target = self
        slider.action = #selector(sliderChanged)
        slider.isContinuous = true
        slider.widthAnchor.constraint(equalToConstant: sliderWidth).isActive = true

        var views: [NSView] = []
        if let label = label {
            labels = (DisplayName.abbreviated(label), label)
            let button = NSButton(title: "", target: self, action: #selector(toggleLabel))
            button.isBordered = false
            labelButton = button
            updateLabel()
            views.append(button)
        }
        views += [iconButton(icons.darker, action: #selector(stepDown)), slider, iconButton(icons.brighter, action: #selector(stepUp))]

        let stack = NSStackView(views: views)
        stack.orientation = .horizontal
        stack.spacing = 10
        stack.edgeInsets = NSEdgeInsets(top: 0, left: 12, bottom: 0, right: 12)
        if let label = views.first, views.count == 4 {
            stack.setCustomSpacing(14, after: label)
        }

        let capsule = NSView()
        capsule.wantsLayer = true
        capsule.layer?.backgroundColor = Self.capsuleColor.cgColor
        capsule.layer?.cornerRadius = 6
        capsule.layer?.cornerCurve = .continuous
        stack.translatesAutoresizingMaskIntoConstraints = false
        capsule.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: capsule.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: capsule.trailingAnchor),
            stack.topAnchor.constraint(equalTo: capsule.topAnchor),
            stack.bottomAnchor.constraint(equalTo: capsule.bottomAnchor),
            capsule.heightAnchor.constraint(equalToConstant: 30),
        ])
        view = capsule

        refresh()
        let timer = Timer(timeInterval: 0.5, repeats: true) { [weak self] _ in self?.refresh() }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        timer?.invalidate()
    }

    private func iconButton(_ image: NSImage, action: Selector) -> NSButton {
        let button = NSButton(image: image, target: self, action: action)
        button.isBordered = false
        button.imageScaling = .scaleNone
        return button
    }

    @objc private func toggleLabel() {
        showsFullLabel.toggle()
        updateLabel()
        view.layoutSubtreeIfNeeded()
        onResize?()
    }

    private func updateLabel() {
        guard let labels = labels else { return }
        labelButton?.attributedTitle = NSAttributedString(string: showsFullLabel ? labels.full : labels.short, attributes: [
            .foregroundColor: NSColor(white: 0.75, alpha: 1),
            .font: NSFont.systemFont(ofSize: 13),
        ])
    }

    @objc private func stepDown() {
        set(slider.floatValue - Self.step)
    }

    @objc private func stepUp() {
        set(slider.floatValue + Self.step)
    }

    @objc private func sliderChanged() {
        write(slider.floatValue)
    }

    private func set(_ value: Float) {
        slider.floatValue = min(max(value, 0), 1)
        write(slider.floatValue)
    }

    private func refresh() {
        if let value = read() {
            slider.floatValue = value
        }
    }
}

/// Slider drawing like Apple's Touch Bar sliders: thin track, blue up to the knob, and a
/// small white knob instead of the large default one.
final class CompactSliderCell: NSSliderCell {
    private static let knobSize = NSSize(width: 20, height: 22)
    private static let trackHeight: CGFloat = 4

    override var knobThickness: CGFloat {
        Self.knobSize.width
    }

    override func barRect(flipped _: Bool) -> NSRect {
        controlView?.bounds ?? .zero
    }

    override func knobRect(flipped: Bool) -> NSRect {
        let bounds = barRect(flipped: flipped)
        let range = maxValue - minValue
        let fraction = range > 0 ? CGFloat((doubleValue - minValue) / range) : 0
        return NSRect(x: bounds.minX + (bounds.width - Self.knobSize.width) * fraction,
                      y: bounds.midY - Self.knobSize.height / 2,
                      width: Self.knobSize.width, height: Self.knobSize.height)
    }

    override func drawBar(inside rect: NSRect, flipped: Bool) {
        let bounds = barRect(flipped: flipped)
        let track = NSRect(x: bounds.minX + Self.knobSize.width / 2, y: bounds.midY - Self.trackHeight / 2,
                           width: bounds.width - Self.knobSize.width, height: Self.trackHeight)
        let radius = Self.trackHeight / 2
        NSColor(white: 0.5, alpha: 1).setFill()
        NSBezierPath(roundedRect: track, xRadius: radius, yRadius: radius).fill()

        var filled = track
        filled.size.width = knobRect(flipped: flipped).midX - track.minX
        NSColor.systemBlue.setFill()
        NSBezierPath(roundedRect: filled, xRadius: radius, yRadius: radius).fill()
    }

    override func drawKnob(_ knobRect: NSRect) {
        NSColor.white.setFill()
        NSBezierPath(roundedRect: knobRect, xRadius: 5, yRadius: 5).fill()
    }
}

/// Apple's own Touch Bar brightness icons, loaded from macOS at runtime (nothing is copied into
/// this repository). SF Symbols are the fallback in case a future macOS drops them.
struct DisplayIcons {
    let darker: NSImage
    let brighter: NSImage

    private static let controlStrip = Bundle(path: "/System/Library/CoreServices/ControlStrip.app")

    /// Laptop with a dark / bright screen, from the Control Strip.
    static let builtIn = DisplayIcons(
        darker: load("BrightnessBuiltInMin", fallback: "laptopcomputer"),
        brighter: load("BrightnessBuiltInMax", fallback: "laptopcomputer")
    )
    /// Monitor with a dark / bright screen, from the Control Strip.
    static let external = DisplayIcons(
        darker: load("BrightnessExternalMin", fallback: "display"),
        brighter: load("BrightnessExternalMax", fallback: "display")
    )
    /// The sun of Apple's Control Strip brightness button (an AppKit Touch Bar image).
    static let sun = white(NSImage(named: "NSTouchBarControlStripDisplayBrightnessUpTemplate")
        ?? NSImage(systemSymbolName: "sun.max.fill", accessibilityDescription: "Brightness")!)

    private static func load(_ name: String, fallback symbol: String) -> NSImage {
        white(controlStrip?.image(forResource: name)
            ?? NSImage(systemSymbolName: symbol, accessibilityDescription: nil)!)
    }

    /// Template images render dimmed in borderless Touch Bar buttons; paint them solid white.
    private static func white(_ template: NSImage) -> NSImage {
        let image = NSImage(size: template.size, flipped: false) { rect in
            template.draw(in: rect)
            NSColor.white.set()
            rect.fill(using: .sourceAtop)
            return true
        }
        image.isTemplate = false
        return image
    }
}
