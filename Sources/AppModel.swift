import Cocoa
import SwiftUI
import AVFoundation
import Carbon
import ServiceManagement

struct SoundProfile: Decodable, Identifiable {
    let id: String
    let name: String
    let subtitle: String
    let detail: String
    let author: String
    let url: String
    let waveform: [Double]
}

struct PreviewKey: Identifiable {
    let name: String
    let code: UInt16
    var id: UInt16 { code }
    static let all: [PreviewKey] = [
        .init(name:"普通键",code:0), .init(name:"Tab",code:48), .init(name:"Caps Lock",code:57),
        .init(name:"左 Shift",code:56), .init(name:"右 Shift",code:60), .init(name:"⌫",code:51),
        .init(name:"Enter",code:36), .init(name:"空格",code:49)
    ]
}

final class AppModel: ObservableObject {
    let engine: OpaquePointer
    let profiles: [SoundProfile]
    let monitor: KeyMonitor
    @Published var language: AppLanguage {
        didSet { language.save(); refreshDevice(); changed?() }
    }
    func text(_ source: String) -> String { language.text(source) }
    @Published var selected: Int { didSet { UserDefaults.standard.set(profile.id, forKey: "profileID"); sync() } }
    @Published var volume: Double { didSet { UserDefaults.standard.set(volume, forKey: "volume"); sync() } }
    @Published var natural: Bool { didSet { UserDefaults.standard.set(natural, forKey: "natural"); sync() } }
    @Published var differentKeys: Bool { didSet { UserDefaults.standard.set(differentKeys, forKey:"differentKeys"); sync() } }
    @Published var previewKey: UInt16 = 0
    @Published var enabled: Bool { didSet { UserDefaults.standard.set(enabled, forKey: "enabled"); updateRunning() } }
    @Published var permission = false
    @Published var listening = false
    @Published var secureInput = false
    @Published private var errorKey = ""
    @Published private var errorDetail = ""
    var error: String { errorKey.isEmpty ? "" : text(errorKey) + (errorDetail.isEmpty ? "" : ": " + errorDetail) }
    @Published var deviceInfo = ""
    @Published var loginEnabled = false
    var changed: (() -> Void)?
    var diagnosticReportURL: URL?
    var timer: Timer?
    private var audioRunning = false
    private var previewGeneration = 0
    private var observers: [NSObjectProtocol] = []
    private var suspended = false

    init() throws {
        language = AppLanguage.saved()
        guard let engine = kt_create() else { throw NSError(domain:"KeyTone",code:1,userInfo:[NSLocalizedDescriptionKey:AppLanguage.saved().text("无法分配音频内存")]) }
        self.engine = engine
        monitor = KeyMonitor(engine: engine)
        guard let resource = Bundle.main.resourceURL else { throw NSError(domain:"KeyTone",code:2) }
        profiles = try JSONDecoder().decode([SoundProfile].self, from: Data(contentsOf: resource.appendingPathComponent("profiles.json")))
        guard profiles.count == 10 else { throw NSError(domain:"KeyTone",code:3) }
        let defaults = UserDefaults.standard
        defaults.register(defaults:["volume":0.5,"natural":true,"differentKeys":true,"enabled":false])
        // Version 1.0 numeric indices refer to retired recordings. Preserve other preferences,
        // but choose the new recommended profile on the first upgrade; then persist by stable ID.
        selected = profiles.firstIndex(where:{$0.id == defaults.string(forKey:"profileID")}) ?? 0
        volume = min(1,max(0,defaults.double(forKey:"volume")))
        natural = defaults.bool(forKey:"natural")
        differentKeys = defaults.bool(forKey:"differentKeys")
        enabled = defaults.bool(forKey:"enabled")
        for (index, profile) in profiles.enumerated() {
            for variant in 0..<Int(KT_SAMPLES_PER_PROFILE) {
                let url = resource.appendingPathComponent("Sounds/\(profile.id)-\(variant).wav")
                let file = try AVAudioFile(forReading:url, commonFormat:.pcmFormatFloat32, interleaved:false)
                guard file.processingFormat.sampleRate == 48000, file.processingFormat.channelCount == 1,
                      let buffer = AVAudioPCMBuffer(pcmFormat:file.processingFormat, frameCapacity:AVAudioFrameCount(file.length)) else {
                    throw NSError(domain:"KeyTone",code:4,userInfo:[NSLocalizedDescriptionKey:AppLanguage.saved().text("音色文件格式错误")])
                }
                try file.read(into:buffer)
                guard let samples = buffer.floatChannelData?[0], kt_load(engine,Int32(index*Int(KT_SAMPLES_PER_PROFILE)+variant),samples,buffer.frameLength) else {
                    throw NSError(domain:"KeyTone",code:5,userInfo:[NSLocalizedDescriptionKey:AppLanguage.saved().text("音色载入失败")])
                }
            }
        }
        loginEnabled = SMAppService.mainApp.status == .enabled
        sync()
    }
    func begin() {
        updateRunning()
        timer = Timer.scheduledTimer(withTimeInterval:2,repeats:true) { [weak self] _ in self?.refresh() }
        let center = NSWorkspace.shared.notificationCenter
        observers.append(center.addObserver(forName:NSWorkspace.willSleepNotification,object:nil,queue:.main) { [weak self] _ in
            guard let self else {return}; suspended = true; monitor.stop(); listening = false; stopAudio()
        })
        observers.append(center.addObserver(forName:NSWorkspace.didWakeNotification,object:nil,queue:.main) { [weak self] _ in
            guard let self else {return}; suspended = false; updateRunning()
        })
    }
    var profile: SoundProfile { profiles[selected] }
    var status: String {
        if !error.isEmpty { return error }
        if !enabled { return text("已暂停 · 可以先试听音色") }
        if !permission { return text("需要开启输入监控") }
        if secureInput { return text("安全输入中 · 系统暂时屏蔽按键") }
        if !listening { return text("监听未启动 · 请检查权限后重新打开") }
        return text("正在聆听 · 每次按下，响一声")
    }
    func sync() {
        kt_configure(engine,Int32(selected),Float(volume),natural,enabled)
        kt_set_key_variation(engine,differentKeys)
        changed?()
    }
    @discardableResult func startAudio() -> Bool {
        if audioRunning { return true }
        let status = kt_start(engine)
        if status != 0 { errorKey = "音频启动失败"; errorDetail = String(status); return false }
        audioRunning = true; errorKey = ""; errorDetail = ""; return true
    }
    func stopAudio() {
        previewGeneration += 1
        kt_stop(engine); audioRunning = false
    }
    func updateRunning() {
        sync()
        permission = CGPreflightListenEventAccess()
        if enabled && permission && !suspended {
            if startAudio() { listening = monitor.start() }
            if !listening { stopAudio() }
        } else {
            monitor.stop(); listening = false; stopAudio()
        }
        refreshDevice()
        changed?()
    }
    func refresh() {
        let allowed = CGPreflightListenEventAccess()
        if allowed != permission || (enabled && allowed && !listening && !suspended) { updateRunning() }
        secureInput = IsSecureEventInputEnabled()
        refreshDevice()
        changed?()
        writeDiagnosticReport()
    }
    func refreshDevice() {
        if audioRunning { kt_refresh_device(engine) }
        let rate = kt_device_rate(engine), frames = kt_buffer_frames(engine)
        if rate > 0 { deviceInfo = String(format:text("设备缓冲 %.1f ms · %.0f kHz"),Double(frames)/rate*1000,rate/1000) }
        else { deviceInfo = text("未检测到音频输出设备") }
    }
    func preview() {
        guard !suspended, startAudio() else { return }
        sync(); kt_trigger(engine,true,previewKey,mach_absolute_time())
        previewGeneration += 1
        let token = previewGeneration
        DispatchQueue.main.asyncAfter(deadline:.now()+0.6) { [weak self] in
            guard let self, token == previewGeneration, !listening else { return }
            stopAudio()
        }
    }
    func requestPermission() {
        _ = CGRequestListenEventAccess()
        if let url = URL(string:"x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent") { NSWorkspace.shared.open(url) }
    }
    var diagnosticSnapshot: [String:Any] {
        ["version":Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "unknown",
         "build":Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "unknown",
         "bundle":Bundle.main.bundlePath,"pid":ProcessInfo.processInfo.processIdentifier,
         "sampledAt":Date().timeIntervalSince1970,"profiles":profiles.count,"language":language.rawValue,
         "permission":CGPreflightListenEventAccess(),"enabled":enabled,"listening":listening,
         "audioRunning":audioRunning,"secureInput":secureInput,"device":deviceInfo,
         "appVolume":volume,"inputSoundsRendered":kt_input_count(engine),
         "allSoundsRendered":kt_count(engine),"dropped":kt_dropped(engine),"error":error]
    }
    func writeDiagnosticReport() {
        guard let url=diagnosticReportURL, let data=try? JSONSerialization.data(withJSONObject:diagnosticSnapshot,options:[.prettyPrinted,.sortedKeys]) else {return}
        try? data.write(to:url,options:.atomic)
    }
    func showDiagnostics() {
        refresh()
        let version=Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
        let alert=NSAlert()
        alert.messageText="KeyTone \(version) · \(text("声音检查"))"
        alert.informativeText = [
            text("当前应用：") + Bundle.main.bundlePath,
            text("输入监控：") + text(permission ? "系统已允许" : "系统未授权当前程序"),
            text("键音开关：") + text(enabled ? "已开启" : "已关闭"),
            text("按键监听：") + text(listening ? "运行中" : "未启动"),
            text("音频引擎：") + text(audioRunning ? "运行中" : "暂停或未启动"),
            text("实际按键已播放：") + String(kt_input_count(engine)),
            "",
            text("试听按钮无需输入监控。若试听有声、敲键无声，优先检查权限。设置里有旧条目时，移除后重新加入上面的这个应用；系统要求重启时，退出后重新打开。")
        ].joined(separator:"\n")
        alert.addButton(withTitle:text("关闭"))
        alert.addButton(withTitle:text("打开权限设置"))
        alert.addButton(withTitle:text("显示当前应用"))
        switch alert.runModal() {
        case .alertSecondButtonReturn:requestPermission()
        case .alertThirdButtonReturn:NSWorkspace.shared.activateFileViewerSelecting([Bundle.main.bundleURL])
        default:break
        }
    }
    func setLogin(_ enabled: Bool) {
        do {
            if enabled { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            loginEnabled = SMAppService.mainApp.status == .enabled
            if enabled && !loginEnabled { SMAppService.openSystemSettingsLoginItems() }
        } catch { errorKey = "登录启动设置失败"; errorDetail = error.localizedDescription }
    }
    func shutdown() {
        timer?.invalidate()
        for observer in observers { NSWorkspace.shared.notificationCenter.removeObserver(observer) }
        monitor.stop(); stopAudio(); kt_destroy(engine)
    }
}
