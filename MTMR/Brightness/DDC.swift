import Foundation

/// DDC/CI message encoding (VESA MCCS), independent of the transport.
///
/// Byte layout and checksums follow m1ddc and MonitorControl, which use the same framing
/// over `IOAVServiceWriteI2C` on Apple Silicon.
enum DDC {
    /// 7-bit I2C address of the monitor's DDC/CI endpoint.
    static let chipAddress: UInt32 = 0x37
    /// Host (source) address, sent as the I2C sub-address.
    static let dataAddress: UInt32 = 0x51
    /// VCP code for luminance (brightness).
    static let brightness: UInt8 = 0x10
    /// Size of a "Get VCP Feature" reply as returned by `IOAVServiceReadI2C`.
    static let replyLength = 11

    static func setVCPPacket(code: UInt8, value: UInt16) -> [UInt8] {
        let body: [UInt8] = [0x84, 0x03, code, UInt8(value >> 8), UInt8(value & 0xFF)]
        return body + [checksum(seed: 0x6E ^ 0x51, body)]
    }

    static func getVCPPacket(code: UInt8) -> [UInt8] {
        let body: [UInt8] = [0x82, 0x01, code]
        return body + [checksum(seed: 0x6E, body)]
    }

    /// Parses a "Get VCP Feature" reply: `[src, len, 0x02, result, code, type, maxHi, maxLo, curHi, curLo, checksum]`.
    static func parseVCPReply(_ reply: [UInt8], code: UInt8) -> (current: UInt16, max: UInt16)? {
        guard reply.count >= replyLength else { return nil }
        let frame = Array(reply.prefix(replyLength))
        guard checksum(seed: 0x50, frame.dropLast()) == frame[10],
              frame[2] == 0x02, // reply opcode
              frame[3] == 0x00, // result: no error
              frame[4] == code
        else { return nil }
        let max = UInt16(frame[6]) << 8 | UInt16(frame[7])
        let current = UInt16(frame[8]) << 8 | UInt16(frame[9])
        return (current, max)
    }

    /// Maps a built-in brightness level (0…1) linearly onto the monitor's range (0…max).
    static func value(forLevel level: Float, max: UInt16) -> UInt16 {
        let clamped = Swift.min(Swift.max(level, 0), 1)
        return UInt16((Float(max) * clamped).rounded())
    }

    static func checksum<S: Sequence>(seed: UInt8, _ bytes: S) -> UInt8 where S.Element == UInt8 {
        bytes.reduce(seed, ^)
    }
}
