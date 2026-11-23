import Cocoa

final class TimeItem: ButtonItem {
    private let formatter = DateFormatter()
    private var timer: Timer?

    init(identifier: NSTouchBarItem.Identifier, formatTemplate: String, timeZone: String?, locale: String?) {
        formatter.dateFormat = formatTemplate
        if let locale = locale {
            formatter.locale = Locale(identifier: locale)
        }
        if let zone = timeZone {
            formatter.timeZone = TimeZone(abbreviation: zone) ?? TimeZone(identifier: zone)
        }
        super.init(identifier: identifier, title: " ")
        isBordered = false
        updateTime()
        let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in self?.updateTime() }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        timer?.invalidate()
    }

    private func updateTime() {
        title = formatter.string(from: Date())
    }
}
