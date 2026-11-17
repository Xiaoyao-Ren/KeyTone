import SwiftUI

private let accent = Color(red:0.25,green:0.72,blue:0.57)
struct MainView: View {
    @ObservedObject var model: AppModel
    var body: some View {
        VStack(spacing:0) {
            HStack(spacing:14) {
                Image(systemName:"pianokeys").font(.system(size:27,weight:.medium)).foregroundStyle(accent)
                VStack(alignment:.leading,spacing:3) {
                    HStack(alignment:.firstTextBaseline,spacing:8) {
                        Text("KeyTone").font(.system(size:26,weight:.semibold,design:.rounded))
                        Text(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "").font(.system(size:11,design:.monospaced)).foregroundStyle(.secondary)
                    }
                    Text(model.text("让每一次敲击，都有喜欢的声音。")).font(.system(size:12)).foregroundStyle(.secondary)
                }
                Spacer()
                Toggle(model.text("开启键音"),isOn:$model.enabled).toggleStyle(.switch).tint(accent)
            }.padding(24)
            Divider()
            HStack(spacing:0) {
                VStack(alignment:.leading,spacing:10) {
                    Text(model.text("10 种真实键盘音色")).font(.system(size:11,weight:.medium)).foregroundStyle(.secondary).padding(.horizontal,12)
                    ScrollView {
                        VStack(spacing:4) {
                            ForEach(Array(model.profiles.enumerated()), id:\.element.id) { index, profile in
                                Button { model.selected = index; model.preview() } label: {
                                    HStack(spacing:10) {
                                        Text(String(format:"%02d",index+1)).font(.system(size:11,design:.monospaced)).foregroundStyle(model.selected == index ? accent : .secondary)
                                        VStack(alignment:.leading,spacing:3) {
                                            Text(model.text(profile.name)).font(.system(size:13,weight:.medium))
                                            Text(model.text(profile.subtitle)).font(.system(size:10)).foregroundStyle(.secondary)
                                        }
                                        Spacer(minLength:0)
                                        if model.selected == index { Image(systemName:"waveform").foregroundStyle(accent) }
                                    }.padding(.horizontal,12).padding(.vertical,4).contentShape(Rectangle())
                                        .background(model.selected == index ? accent.opacity(0.13) : .clear,in:RoundedRectangle(cornerRadius:9))
                                }.buttonStyle(.plain).accessibilityLabel("\(model.text(profile.name)), \(model.text(profile.subtitle)), \(model.text("选择并试听"))")
                            }
                        }
                    }
                }.padding(12).frame(width:270)
                Divider()
                VStack(alignment:.leading,spacing:14) {
                    HStack { Label(model.text("真实按键采样"),systemImage:"waveform"); Spacer(); Text("MIT") }.font(.system(size:10,weight:.medium)).foregroundStyle(accent)
                    VStack(alignment:.leading,spacing:7) {
                        Text(model.text(model.profile.name)).font(.system(size:25,weight:.semibold,design:.rounded))
                        Text(model.text(model.profile.detail)).font(.system(size:12)).foregroundStyle(.secondary).fixedSize(horizontal:false,vertical:true).lineSpacing(3)
                    }
                    GeometryReader { geometry in
                        HStack(alignment:.center,spacing:3) {
                            ForEach(Array(model.profile.waveform.enumerated()),id:\.offset) { _,value in
                                Capsule().fill(accent.opacity(0.7)).frame(width:max(2,(geometry.size.width-3*39)/40),height:max(3,CGFloat(value)*38))
                            }
                        }.frame(height:42)
                    }.frame(height:42).accessibilityHidden(true)
                    VStack(alignment:.leading,spacing:8) {
                        Text(model.text("点击试听不同按键")).font(.system(size:10)).foregroundStyle(.secondary)
                        LazyVGrid(columns:Array(repeating:GridItem(.flexible(),spacing:6),count:4),spacing:6) {
                            ForEach(PreviewKey.all) { key in
                                Button { model.previewKey=key.code;model.preview() } label: {
                                    Text(model.text(key.name)).font(.system(size:11,weight:.medium)).frame(maxWidth:.infinity).padding(.vertical,8)
                                        .background(model.previewKey == key.code ? accent.opacity(0.20) : Color.primary.opacity(0.055),in:RoundedRectangle(cornerRadius:7))
                                        .overlay(RoundedRectangle(cornerRadius:7).stroke(model.previewKey == key.code ? accent.opacity(0.65) : .clear,lineWidth:1))
                                }.buttonStyle(.plain).accessibilityLabel("\(model.text("试听")) \(model.text(key.name))")
                            }
                        }
                    }
                    VStack(alignment:.leading,spacing:8) {
                        HStack { Text(model.text("音量")); Spacer(); Text("\(Int(model.volume*100))%").monospacedDigit().foregroundStyle(.secondary) }
                        Slider(value:$model.volume,in:0...1).tint(accent).accessibilityLabel(model.text("音效音量"))
                    }.font(.system(size:12))
                    Toggle(isOn:$model.natural) {
                        VStack(alignment:.leading,spacing:3) {
                            Text(model.text("自然变化")).font(.system(size:12))
                            Text(model.text("普通键实录轮换，避免连续重复")).font(.system(size:10)).foregroundStyle(.secondary)
                        }
                    }.toggleStyle(.switch).controlSize(.small).tint(accent)
                    Toggle(isOn:$model.differentKeys) {
                        VStack(alignment:.leading,spacing:3) {
                            Text(model.text("真实大键声音")).font(.system(size:12))
                            Text(model.text("空格、Enter、Shift 等使用各自实录")).font(.system(size:10)).foregroundStyle(.secondary)
                        }
                    }.toggleStyle(.switch).controlSize(.small).tint(accent)
                    Toggle(model.text("登录时启动"),isOn:Binding(get:{model.loginEnabled},set:{model.setLogin($0)})).toggleStyle(.switch).controlSize(.small).tint(accent).font(.system(size:12))
                    Picker(model.text("语言"), selection:$model.language) {
                        ForEach(AppLanguage.allCases) { language in
                            Text(language.displayName).tag(language)
                        }
                    }.pickerStyle(.menu).font(.system(size:12))
                    Spacer(minLength:0)
                    if let url = URL(string:model.profile.url) {
                        Link("\(model.text("录音："))\(model.profile.author) ↗",destination:url).font(.system(size:10)).foregroundStyle(.secondary)
                    }
                    Text(model.text("推荐内置扬声器或有线耳机。长按只响一次。\nTab / Caps Lock 也有独立实录，不人为降调。")).font(.system(size:10)).foregroundStyle(.secondary).lineSpacing(3)
                }.padding(24).frame(maxWidth:.infinity,maxHeight:.infinity,alignment:.topLeading)
            }
            Divider()
            HStack(spacing:10) {
                Circle().fill(model.enabled && model.listening && !model.secureInput ? accent : .orange).frame(width:7,height:7)
                VStack(alignment:.leading,spacing:3) {
                    Text(model.status).font(.system(size:11,weight:.medium))
                    Text(model.deviceInfo + model.text(" · 本地运行，不记录输入内容")).font(.system(size:9)).foregroundStyle(.secondary)
                }
                Spacer()
                Button(model.text("检查状态")) { model.showDiagnostics() }.controlSize(.small)
                if !model.permission { Button(model.text("开启输入监控")) { model.requestPermission() }.controlSize(.small) }
            }.padding(.horizontal,24).padding(.vertical,14)
        }.frame(width:760,height:790).background(Color(nsColor:.windowBackgroundColor))
            .environment(\.locale,Locale(identifier:model.language.rawValue))
    }
}
