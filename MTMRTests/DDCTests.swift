import XCTest

final class DDCTests: XCTestCase {
    func testSetBrightnessPacket() {
        // Same bytes m1ddc sends for `set luminance 50`.
        let packet = DDC.setVCPPacket(code: DDC.brightness, value: 50)
        XCTAssertEqual(packet, [0x84, 0x03, 0x10, 0x00, 0x32, 0x6E ^ 0x51 ^ 0x84 ^ 0x03 ^ 0x10 ^ 0x00 ^ 0x32])
    }

    func testSetPacketSplitsLargeValues() {
        let packet = DDC.setVCPPacket(code: 0x10, value: 0x0123)
        XCTAssertEqual(Array(packet[3 ... 4]), [0x01, 0x23])
    }

    func testGetBrightnessPacket() {
        XCTAssertEqual(DDC.getVCPPacket(code: 0x10), [0x82, 0x01, 0x10, 0x6E ^ 0x82 ^ 0x01 ^ 0x10])
    }

    private func reply(code: UInt8 = 0x10, result: UInt8 = 0x00, max: UInt16, current: UInt16) -> [UInt8] {
        var frame: [UInt8] = [0x6E, 0x88, 0x02, result, code, 0x00,
                              UInt8(max >> 8), UInt8(max & 0xFF), UInt8(current >> 8), UInt8(current & 0xFF)]
        frame.append(frame.reduce(0x50, ^))
        return frame
    }

    func testParsesValidReply() {
        let parsed = DDC.parseVCPReply(reply(max: 100, current: 37), code: 0x10)
        XCTAssertEqual(parsed?.max, 100)
        XCTAssertEqual(parsed?.current, 37)
    }

    func testRejectsBadChecksum() {
        var frame = reply(max: 100, current: 37)
        frame[10] ^= 0xFF
        XCTAssertNil(DDC.parseVCPReply(frame, code: 0x10))
    }

    func testRejectsUnsupportedCodeAndWrongCode() {
        XCTAssertNil(DDC.parseVCPReply(reply(result: 0x01, max: 100, current: 37), code: 0x10))
        XCTAssertNil(DDC.parseVCPReply(reply(code: 0x12, max: 100, current: 37), code: 0x10))
    }

    func testRejectsShortReply() {
        XCTAssertNil(DDC.parseVCPReply([0x6E, 0x88], code: 0x10))
    }

    func testLevelMapping() {
        XCTAssertEqual(DDC.value(forLevel: 0, max: 100), 0)
        XCTAssertEqual(DDC.value(forLevel: 0.5, max: 100), 50)
        XCTAssertEqual(DDC.value(forLevel: 1, max: 100), 100)
        XCTAssertEqual(DDC.value(forLevel: 0.5, max: 255), 128)
        XCTAssertEqual(DDC.value(forLevel: 1.4, max: 100), 100)
        XCTAssertEqual(DDC.value(forLevel: -0.2, max: 100), 0)
    }
}

final class DisplayNameTests: XCTestCase {
    func testKeepsShortNames() {
        XCTAssertEqual(DisplayName.short("DELL U2720Q"), "DELL U2720Q")
        XCTAssertEqual(DisplayName.short("LG HDR 4K"), "LG HDR 4K")
    }

    func testCutsAtWordBoundary() {
        XCTAssertEqual(DisplayName.short("Built-in Retina Display"), "Built-in")
        XCTAssertEqual(DisplayName.short("Samsung Odyssey G9 Monitor"), "Samsung")
    }

    func testKeepsOverlongFirstWord() {
        XCTAssertEqual(DisplayName.short("VeryLongMonitorName2000"), "VeryLongMonitorName2000")
    }
}

final class DisplayNameAbbreviationTests: XCTestCase {
    func testAbbreviatesLongNames() {
        XCTAssertEqual(DisplayName.abbreviated("P27h-30"), "P27h…")
        XCTAssertEqual(DisplayName.abbreviated("DELL U2720Q"), "DELL…")
    }

    func testKeepsNamesThatAreShortAlready() {
        XCTAssertEqual(DisplayName.abbreviated("LG"), "LG")
        XCTAssertEqual(DisplayName.abbreviated("LG 4K"), "LG 4K")
    }
}
