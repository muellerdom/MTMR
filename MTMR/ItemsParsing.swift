import Foundation

/// One entry of `items.json`.
struct BarItemDefinition: Decodable, Equatable {
    let type: ItemType
    let align: Align
    let width: CGFloat?
    let bordered: Bool?

    private enum CodingKeys: String, CodingKey {
        case type, align, width, bordered
    }

    init(type: ItemType, align: Align = .center, width: CGFloat? = nil, bordered: Bool? = nil) {
        self.type = type
        self.align = align
        self.width = width
        self.bordered = bordered
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        type = try ItemType(from: decoder)
        align = try container.decodeIfPresent(Align.self, forKey: .align) ?? type.defaultAlign
        width = try container.decodeIfPresent(CGFloat.self, forKey: .width)
        bordered = try container.decodeIfPresent(Bool.self, forKey: .bordered)
    }
}

enum ItemType: Decodable, Equatable {
    case escape
    case brightnessDown
    case brightnessUp
    /// Sun button that expands into one brightness slider per display.
    case brightness
    case volumeDown
    case volumeUp
    case mute
    case play
    case timeButton(formatTemplate: String, timeZone: String?, locale: String?)
    /// A type this build does not support (e.g. a widget from the full MTMR). It is skipped.
    case unsupported(String)

    private enum CodingKeys: String, CodingKey {
        case type, formatTemplate, timeZone, locale
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(String.self, forKey: .type)
        switch type {
        case "escape": self = .escape
        case "brightnessDown": self = .brightnessDown
        case "brightnessUp": self = .brightnessUp
        case "brightness": self = .brightness
        case "volumeDown": self = .volumeDown
        case "volumeUp": self = .volumeUp
        case "mute": self = .mute
        case "play": self = .play
        case "timeButton":
            self = .timeButton(
                formatTemplate: try container.decodeIfPresent(String.self, forKey: .formatTemplate) ?? "HH:mm",
                timeZone: try container.decodeIfPresent(String.self, forKey: .timeZone),
                locale: try container.decodeIfPresent(String.self, forKey: .locale)
            )
        default: self = .unsupported(type)
        }
    }

    var defaultAlign: Align {
        self == .escape ? .left : .center
    }
}

enum Align: String, Decodable {
    case left
    case center
    case right
}

enum PresetError: Error {
    case notUTF8
}

extension BarItemDefinition {
    /// Decodes a preset. `//` line comments and `/* */` block comments are allowed.
    /// Unsupported item types are dropped.
    static func parsePreset(_ data: Data) throws -> [BarItemDefinition] {
        guard let text = String(data: data, encoding: .utf8) else { throw PresetError.notUTF8 }
        let items = try JSONDecoder().decode([BarItemDefinition].self, from: Data(text.strippingComments().utf8))
        return items.filter {
            if case let .unsupported(name) = $0.type {
                NSLog("MTMR: skipping unsupported item type \"%@\"", name)
                return false
            }
            return true
        }
    }
}

extension String {
    /// Removes `/* … */` and `//` comments that start a line or follow whitespace or a comma,
    /// so that `//` inside a value such as `"https://…"` stays intact.
    func strippingComments() -> String {
        self
            .replacingOccurrences(of: #"(^|[\s,])/\*[\s\S]*?\*/"#, with: "$1", options: .regularExpression)
            .replacingOccurrences(of: #"(?m)(^|[\s,])//.*$"#, with: "$1", options: .regularExpression)
    }
}
