import Cocoa

/// The single item MTMR hands to the Touch Bar: left items, a scrollable center, right items.
final class RootItem: NSCustomTouchBarItem {
    init(identifier: NSTouchBarItem.Identifier, left: [NSTouchBarItem], center: [NSTouchBarItem], right: [NSTouchBarItem]) {
        super.init(identifier: identifier)

        let centerStack = NSStackView(views: center.compactMap(\.view))
        centerStack.orientation = .horizontal
        centerStack.spacing = 1
        let centerScroll = NSScrollView(frame: CGRect(origin: .zero, size: centerStack.fittingSize))
        centerScroll.documentView = centerStack

        let stack = NSStackView(views: left.compactMap(\.view) + [centerScroll] + right.compactMap(\.view))
        stack.orientation = .horizontal
        stack.spacing = 8
        view = stack
    }

    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

/// A row that can be swiped sideways. It scrolls past its last item by that item's width
/// (plus spacing), so the end of the row is never stuck at the Touch Bar's edge.
/// Swipes that start on a slider are left to the slider.
final class ScrollingRowItem: NSCustomTouchBarItem, NSGestureRecognizerDelegate {
    private let clip = NSView()
    private let content: NSStackView
    private let maxWidth: CGFloat
    private let widthConstraint: NSLayoutConstraint
    private var minOffset: CGFloat = 0
    private var startOffset: CGFloat = 0
    private var offset: CGFloat = 0 {
        didSet { content.setFrameOrigin(NSPoint(x: offset, y: 0)) }
    }

    init(identifier: NSTouchBarItem.Identifier, items: [NSTouchBarItem], spacing: CGFloat, maxWidth: CGFloat) {
        content = NSStackView(views: items.compactMap(\.view))
        content.orientation = .horizontal
        content.spacing = spacing
        self.maxWidth = maxWidth
        widthConstraint = clip.widthAnchor.constraint(equalToConstant: 0)
        super.init(identifier: identifier)

        clip.wantsLayer = true
        clip.layer?.masksToBounds = true
        clip.addSubview(content)
        NSLayoutConstraint.activate([widthConstraint, clip.heightAnchor.constraint(equalToConstant: 30)])
        let pan = NSPanGestureRecognizer(target: self, action: #selector(panned(_:)))
        pan.allowedTouchTypes = .direct
        pan.delegate = self
        clip.addGestureRecognizer(pan)
        view = clip
        relayout()
    }

    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    /// Re-measures the content, e.g. after a label was expanded.
    func relayout() {
        let width = content.fittingSize.width
        content.frame.size = NSSize(width: width, height: 30)
        widthConstraint.constant = min(width, maxWidth)
        let overscroll = (content.views.last?.fittingSize.width ?? 0) + content.spacing
        minOffset = min(0, widthConstraint.constant - width - overscroll)
        offset = min(0, max(minOffset, offset))
    }

    func gestureRecognizer(_: NSGestureRecognizer, shouldReceive touch: NSTouch) -> Bool {
        let point = touch.location(in: clip)
        return !sliders(in: content).contains { $0.convert($0.bounds, to: clip).contains(point) }
    }

    @objc private func panned(_ pan: NSPanGestureRecognizer) {
        switch pan.state {
        case .began:
            startOffset = offset
        case .changed, .ended:
            offset = min(0, max(minOffset, startOffset + pan.translation(in: clip).x))
        default:
            break
        }
    }

    private func sliders(in view: NSView) -> [NSSlider] {
        view.subviews.flatMap { ($0 as? NSSlider).map { [$0] } ?? sliders(in: $0) }
    }
}
