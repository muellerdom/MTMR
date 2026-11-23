import Foundation
import IOKit

/// An external monitor reachable over DDC/CI through the Apple Silicon display coprocessor.
///
/// Not thread-safe: use one instance from one serial queue. DDC calls block for tens of
/// milliseconds, so keep them off the main thread.
final class ExternalDisplay {
    private let service: CFTypeRef
    /// Highest brightness value the monitor reports; 100 if it does not answer.
    private(set) var maxBrightness: UInt16 = 100
    /// Whether the monitor answered a DDC read, i.e. DDC is known to work on this link.
    private(set) var replied = false
    private var lastSentValue: UInt16?

    private init(service: CFTypeRef) {
        self.service = service
    }

    /// All external displays connected to the DCP. Empty on Intel Macs and for DisplayLink.
    static func all() -> [ExternalDisplay] {
        var iterator = io_iterator_t()
        guard IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching("DCPAVServiceProxy"), &iterator) == KERN_SUCCESS else {
            return []
        }
        defer { IOObjectRelease(iterator) }

        var displays: [ExternalDisplay] = []
        while true {
            let entry = IOIteratorNext(iterator)
            guard entry != 0 else { break }
            defer { IOObjectRelease(entry) }
            let location = IORegistryEntryCreateCFProperty(entry, "Location" as CFString, kCFAllocatorDefault, 0)?
                .takeRetainedValue() as? String
            guard location == "External", let service = IOAVServiceCreateWithService(kCFAllocatorDefault, entry) else {
                continue
            }
            displays.append(ExternalDisplay(service: service))
        }
        return displays
    }

    /// Level (0…1) the monitor reported in `probe()`, if it answered.
    private(set) var initialLevel: Float?

    /// Reads the brightness range once. Call before the first `setBrightness(level:)`.
    func probe() {
        for _ in 0 ..< 3 {
            if let reply = readVCP(DDC.brightness), reply.max > 0 {
                maxBrightness = reply.max
                initialLevel = Float(min(reply.current, reply.max)) / Float(reply.max)
                replied = true
                return
            }
            usleep(20_000)
        }
    }

    /// Sets the monitor to `level` (0…1). Skips the write if the DDC value would not change.
    func setBrightness(level: Float) {
        let value = DDC.value(forLevel: level, max: maxBrightness)
        guard value != lastSentValue else { return }
        var packet = DDC.setVCPPacket(code: DDC.brightness, value: value)
        // Some monitors drop the first write after a pause; sending twice is what MonitorControl does.
        var ok = false
        for _ in 0 ..< 2 {
            if IOAVServiceWriteI2C(service, DDC.chipAddress, DDC.dataAddress, &packet, UInt32(packet.count)) == kIOReturnSuccess {
                ok = true
            }
            usleep(10_000)
        }
        if ok { lastSentValue = value }
    }

    private func readVCP(_ code: UInt8) -> (current: UInt16, max: UInt16)? {
        var request = DDC.getVCPPacket(code: code)
        guard IOAVServiceWriteI2C(service, DDC.chipAddress, DDC.dataAddress, &request, UInt32(request.count)) == kIOReturnSuccess else {
            return nil
        }
        usleep(50_000) // the monitor needs time to prepare the reply
        var reply = [UInt8](repeating: 0, count: DDC.replyLength)
        guard IOAVServiceReadI2C(service, DDC.chipAddress, 0, &reply, UInt32(reply.count)) == kIOReturnSuccess else {
            return nil
        }
        return DDC.parseVCPReply(reply, code: code)
    }
}
