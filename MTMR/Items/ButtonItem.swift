import Cocoa

/// A Touch Bar button that runs a closure on tap.
class ButtonItem: NSCustomTouchBarItem {
    private let button: NSButton
    private let onTap: () -> Void

    init(identifier: NSTouchBarItem.Identifier, title: String = "", image: NSImage? = nil, onTap: @escaping () -> Void = {}) {
        self.onTap = onTap
        button = FixedHeightButton(title: title, target: nil, action: nil)
        super.init(identifier: identifier)
        button.target = self
        button.action = #selector(tapped)
        button.bezelStyle = .rounded
        button.imageScaling = .scaleProportionallyDown
        self.image = image
        self.title = title
        view = button
    }

    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    var title: String {
        get { button.attributedTitle.string }
        set {
            let style = NSMutableParagraphStyle()
            style.alignment = .center
            button.attributedTitle = NSAttributedString(string: newValue, attributes: [
                .foregroundColor: NSColor.white,
                .font: NSFont.systemFont(ofSize: 15),
                .paragraphStyle: style,
            ])
            button.imagePosition = newValue.isEmpty ? .imageOnly : .imageLeading
        }
    }

    var image: NSImage? {
        get { button.image }
        set { button.image = newValue }
    }

    var isBordered: Bool {
        get { button.isBordered }
        set { button.isBordered = newValue }
    }

    @objc private func tapped() {
        onTap()
    }
}

private class FixedHeightButton: NSButton {
    override var intrinsicContentSize: NSSize {
        NSSize(width: super.intrinsicContentSize.width, height: 30)
    }
}
