import CoreGraphics
var filter = PressFilter()
for code: Int64 in [0,1,2,18,19,49,36,53,48,51,123,124,125,126,122] {
    assert(filter.accepts(type:.keyDown,code:code))
    assert(!filter.accepts(type:.keyDown,code:code,repeated:true))
    assert(!filter.accepts(type:.keyUp,code:code))
}
assert(filter.accepts(type:.flagsChanged,code:56,flags:2))
assert(filter.accepts(type:.flagsChanged,code:60,flags:6))
assert(!filter.accepts(type:.flagsChanged,code:56,flags:4))
assert(!filter.accepts(type:.flagsChanged,code:60,flags:0))
for (code,mask): (Int64,UInt64) in [(55,8),(54,16),(59,1),(62,8192),(58,32),(61,64),(63,8388608)] {
    assert(filter.accepts(type:.flagsChanged,code:code,flags:mask))
    assert(!filter.accepts(type:.flagsChanged,code:code,flags:mask))
    assert(!filter.accepts(type:.flagsChanged,code:code,flags:0))
}
assert(filter.accepts(type:.flagsChanged,code:57,flags:CGEventFlags.maskAlphaShift.rawValue))
assert(!filter.accepts(type:.flagsChanged,code:57,flags:CGEventFlags.maskAlphaShift.rawValue))
assert(filter.accepts(type:.flagsChanged,code:57,flags:0))
let media = CGEventType(rawValue:14)!
assert(filter.accepts(type:media,mediaData:0x0a00))
assert(!filter.accepts(type:media,mediaData:0x0b00))
assert(!filter.accepts(type:media,mediaData:0x0a01))
assert(!filter.accepts(type:media))
print("PASS: letters, digits, Escape, Enter, Space, arrows, function keys, repeat filtering, both modifier sides, Caps Lock, Fn, media down/up/repeat.")
