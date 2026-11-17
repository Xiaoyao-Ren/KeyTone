import Cocoa
import Carbon

// Key codes select the recorded key family and distinguish presses from releases.
// No characters are decoded, retained, logged, or transmitted.
final class KeyMonitor {
    let engine: OpaquePointer
    private var tap: CFMachPort?
    private var source: CFRunLoopSource?
    private var loop: CFRunLoop?
    private let finished = DispatchSemaphore(value: 0)
    private var filter = PressFilter()
    init(engine: OpaquePointer) { self.engine = engine }
    var running: Bool { tap != nil }
    func start() -> Bool {
        if running { return true }
        guard CGPreflightListenEventAccess() else { return false }
        let mask = (1 << CGEventType.keyDown.rawValue) | (1 << CGEventType.flagsChanged.rawValue) | (1 << 14)
        guard let port = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap, options: .listenOnly, eventsOfInterest: CGEventMask(mask), callback: { _, type, event, context in
            guard let context else { return Unmanaged.passUnretained(event) }
            let owner = Unmanaged<KeyMonitor>.fromOpaque(context).takeUnretainedValue()
            if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
                if let tap = owner.tap { CGEvent.tapEnable(tap: tap, enable: true) }
            } else {
                var mediaData: Int?
                if type.rawValue == 14, let native = NSEvent(cgEvent:event), native.subtype.rawValue == 8 { mediaData = native.data1 }
                if owner.filter.accepts(type:type,code:event.getIntegerValueField(.keyboardEventKeycode),repeated:event.getIntegerValueField(.keyboardEventAutorepeat) != 0,flags:event.flags.rawValue,mediaData:mediaData) {
                    let code = type.rawValue == 14 ? 0 : UInt16(clamping:event.getIntegerValueField(.keyboardEventKeycode))
                    kt_trigger(owner.engine, false, code, mach_absolute_time())
                }
            }
            return Unmanaged.passUnretained(event)
        }, userInfo: Unmanaged.passUnretained(self).toOpaque()) else { return false }
        tap = port
        filter.modifierFlags = CGEventSource.flagsState(.combinedSessionState).rawValue
        let runSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, port, 0)!
        source = runSource
        let ready = DispatchSemaphore(value: 0)
        let worker = Thread { [self] in
            loop = CFRunLoopGetCurrent()
            CFRunLoopAddSource(loop, runSource, .commonModes)
            CGEvent.tapEnable(tap: port, enable: true)
            ready.signal()
            CFRunLoopRun()
            CFRunLoopRemoveSource(CFRunLoopGetCurrent(), runSource, .commonModes)
            finished.signal()
        }
        worker.name = "KeyTone Input"
        worker.qualityOfService = .userInteractive
        worker.start()
        ready.wait()
        return true
    }
    func stop() {
        guard let port = tap else { return }
        CGEvent.tapEnable(tap: port, enable: false)
        if let loop { CFRunLoopStop(loop); CFRunLoopWakeUp(loop) }
        finished.wait()
        CFMachPortInvalidate(port)
        tap = nil; source = nil; loop = nil
    }
}
