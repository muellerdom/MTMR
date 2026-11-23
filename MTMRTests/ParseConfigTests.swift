import XCTest

final class ParseConfigTests: XCTestCase {
    private func parse(_ json: String) throws -> [BarItemDefinition] {
        try BarItemDefinition.parsePreset(Data(json.utf8))
    }

    func testParsesSupportedItemsWithParameters() throws {
        let items = try parse("""
        [
          { "type": "escape", "width": 64 },
          { "type": "brightness", "width": 40, "align": "right" },
          { "type": "brightnessUp", "bordered": false, "align": "right" },
          { "type": "timeButton", "formatTemplate": "HH:mm:ss", "locale": "de_DE", "align": "right" }
        ]
        """)
        XCTAssertEqual(items, [
            BarItemDefinition(type: .escape, align: .left, width: 64),
            BarItemDefinition(type: .brightness, align: .right, width: 40),
            BarItemDefinition(type: .brightnessUp, align: .right, bordered: false),
            BarItemDefinition(type: .timeButton(formatTemplate: "HH:mm:ss", timeZone: nil, locale: "de_DE"), align: .right),
        ])
    }

    func testDefaults() throws {
        let items = try parse(#"[ { "type": "brightness" }, { "type": "timeButton" } ]"#)
        XCTAssertEqual(items, [
            BarItemDefinition(type: .brightness, align: .center),
            BarItemDefinition(type: .timeButton(formatTemplate: "HH:mm", timeZone: nil, locale: nil), align: .center),
        ])
    }

    func testSkipsTypesFromTheFullMTMR() throws {
        let items = try parse("""
        [
          { "type": "weather", "api_key": "x" },
          { "type": "play" },
          { "type": "volume" },
          { "type": "appleScriptTitledButton", "source": { "inline": "return 1" } }
        ]
        """)
        XCTAssertEqual(items.map(\.type), [.play])
    }

    func testStripsComments() throws {
        let items = try parse("""
        // leading comment
        [
          /* block
             comment */
          { "type": "mute" }, // trailing comment
          { "type": "play" }
        ]
        """)
        XCTAssertEqual(items.map(\.type), [.mute, .play])
    }

    func testKeepsDoubleSlashInsideValues() {
        XCTAssertEqual(#"{ "url": "https://example.com" }"#.strippingComments(), #"{ "url": "https://example.com" }"#)
    }

    func testBundledDefaultPresetParses() throws {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .appendingPathComponent("../MTMR/defaultPreset.json")
        let items = try BarItemDefinition.parsePreset(Data(contentsOf: url))
        XCTAssertTrue(items.contains { $0.type == .brightness })
        XCTAssertTrue(items.contains { $0.type == .escape })
    }

    func testRejectsInvalidJSON() {
        XCTAssertThrowsError(try parse("[ { \"type\": "))
    }
}
