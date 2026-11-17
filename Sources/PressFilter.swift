import CoreGraphics

struct PressFilter {
    var modifierFlags: UInt64 = 0
    // NX device-specific masks distinguish left and right modifiers held together.
    private let masks: [Int64: UInt64] = [56:2,60:4,59:1,62:0x2000,58:0x20,61:0x40,55:8,54:0x10,63:0x800000]
    mutating func accepts(type: CGEventType, code: Int64 = 0, repeated: Bool = false, flags: UInt64 = 0, mediaData: Int? = nil) -> Bool {
        if type == .keyDown { return !repeated }
        if type.rawValue == 14, let mediaData {
            return (mediaData >> 8) & 0xff == 0x0a && mediaData & 1 == 0
        }
        guard type == .flagsChanged else { return false }
        defer { modifierFlags = flags }
        if code == 57 { return (flags ^ modifierFlags) & CGEventFlags.maskAlphaShift.rawValue != 0 }
        guard let mask = masks[code] else { return false }
        return flags & mask != 0 && modifierFlags & mask == 0
    }
}
