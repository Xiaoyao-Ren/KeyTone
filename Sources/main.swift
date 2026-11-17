import Cocoa
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    var model: AppModel!
    var statusItem: NSStatusItem!
    var window: NSWindow!
    let stateItem = NSMenuItem(title:"",action:nil,keyEquivalent:"")
    let toggleItem = NSMenuItem(title:"",action:#selector(toggle),keyEquivalent:"")
    func applicationDidFinishLaunching(_ notification: Notification) {
        let other = NSRunningApplication.runningApplications(withBundleIdentifier:Bundle.main.bundleIdentifier ?? "local.keytone.app").filter{$0.processIdentifier != ProcessInfo.processInfo.processIdentifier}
        if let first = other.first { first.activate(options:[]); NSApp.terminate(nil);return }
        do { model = try AppModel() } catch {
            let alert=NSAlert();alert.messageText=AppLanguage.saved().text("KeyTone 无法启动");alert.informativeText=error.localizedDescription;alert.runModal();NSApp.terminate(nil);return
        }
        statusItem=NSStatusBar.system.statusItem(withLength:NSStatusItem.variableLength)
        statusItem.button?.image=NSImage(systemSymbolName:"keyboard",accessibilityDescription:nil)
        let menu=NSMenu()
        menu.addItem(stateItem);menu.addItem(.separator())
        toggleItem.target=self;menu.addItem(toggleItem)
        let settings=NSMenuItem(title:model.text("音色与设置…"),action:#selector(showWindow),keyEquivalent:",");settings.representedObject="音色与设置…";settings.target=self;menu.addItem(settings)
        let preview=NSMenuItem(title:model.text("试听当前音色"),action:#selector(preview),keyEquivalent:"");preview.representedObject="试听当前音色";preview.target=self;menu.addItem(preview)
        let diagnostics=NSMenuItem(title:model.text("检查声音与权限…"),action:#selector(diagnostics),keyEquivalent:"");diagnostics.representedObject="检查声音与权限…";diagnostics.target=self;menu.addItem(diagnostics)
        menu.addItem(.separator())
        let quit=NSMenuItem(title:model.text("退出 KeyTone"),action:#selector(quit),keyEquivalent:"q");quit.representedObject="退出 KeyTone";quit.target=self;menu.addItem(quit)
        statusItem.menu=menu
        window=NSWindow(contentRect:NSRect(x:0,y:0,width:760,height:790),styleMask:[.titled,.closable,.miniaturizable],backing:.buffered,defer:false)
        window.title="KeyTone \(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "")";window.isReleasedWhenClosed=false;window.delegate=self
        window.contentView=NSHostingView(rootView:MainView(model:model))
        window.center()
        model.changed = { [weak self] in self?.refreshMenu() }
        model.begin();refreshMenu()
        if !UserDefaults.standard.bool(forKey:"hasLaunched") || !model.enabled { showWindow() }
        UserDefaults.standard.set(true,forKey:"hasLaunched")
        if CommandLine.arguments.contains("--diagnostics") {
            print("profiles=\(model.profiles.count) permission=\(model.permission) \(model.deviceInfo)")
            print("audio_start=\(model.startAudio()) device_latency_ms=\(kt_device_latency_ms(model.engine))")
            DispatchQueue.main.asyncAfter(deadline:.now()+1) { NSApp.terminate(nil) }
        }
        if let index = CommandLine.arguments.firstIndex(of:"--capture"), CommandLine.arguments.count > index+1 {
            showWindow()
            let path = CommandLine.arguments[index+1]
            DispatchQueue.main.asyncAfter(deadline:.now()+1) { [self] in
                guard let view = window.contentView, let bitmap = view.bitmapImageRepForCachingDisplay(in:view.bounds) else { return }
                view.cacheDisplay(in:view.bounds,to:bitmap)
                try? bitmap.representation(using:.png,properties:[:])?.write(to:URL(fileURLWithPath:path))
                NSApp.terminate(nil)
            }
        }
        if let index = CommandLine.arguments.firstIndex(of:"--report"), CommandLine.arguments.count > index+1 {
            let path = CommandLine.arguments[index+1]
            if CommandLine.arguments.contains("--watch-report") { model.diagnosticReportURL=URL(fileURLWithPath:path) }
            DispatchQueue.main.asyncAfter(deadline:.now()+2) { [self] in
                if let data = try? JSONSerialization.data(withJSONObject:model.diagnosticSnapshot,options:[.prettyPrinted,.sortedKeys]) { try? data.write(to:URL(fileURLWithPath:path),options:.atomic) }
            }
        }
    }
    func refreshMenu() {
        guard model != nil else{return}
        stateItem.title=model.enabled && model.listening ? "KeyTone · \(model.text(model.profile.name))" : "KeyTone · \(model.status)"
        toggleItem.title=model.text(model.enabled ? "暂停键盘音效" : "开启键盘音效")
        for item in statusItem.menu?.items ?? [] {
            if let source = item.representedObject as? String { item.title = model.text(source) }
        }
        statusItem.button?.setAccessibilityLabel(model.text("KeyTone 键盘音效"))
        statusItem.button?.toolTip=model.text("KeyTone · 点击设置键音")
        window.title="KeyTone \(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "") · \(model.text("键音"))"
        statusItem.button?.appearsDisabled = !model.enabled
    }
    @objc func toggle(){model.enabled.toggle()}
    @objc func preview(){model.preview()}
    @objc func diagnostics(){model.showDiagnostics()}
    @objc func showWindow(){NSApp.activate(ignoringOtherApps:true);window.makeKeyAndOrderFront(nil)}
    @objc func quit(){NSApp.terminate(nil)}
    func applicationShouldHandleReopen(_ sender:NSApplication,hasVisibleWindows flag:Bool)->Bool{showWindow();return true}
    func applicationWillTerminate(_ notification:Notification){model?.shutdown()}
}
let app=NSApplication.shared
app.setActivationPolicy(.accessory)
let delegate=AppDelegate()
app.delegate=delegate
app.run()
