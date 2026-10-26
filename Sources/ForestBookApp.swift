import SwiftUI
import SceneKit

struct ForestBookView: View {
    @StateObject private var model = BookModel()
    private let green = Color(nsColor:NSColor(hex:0x405843))
    var body: some View {
        ZStack {
            Color(nsColor:NSColor(hex:0xFBFAEF)).ignoresSafeArea()
            VStack(spacing:0) {
                HStack(alignment:.top) {
                    VStack(alignment:.leading,spacing:8) {
                        Text("一 本 会 呼 吸 的 立 体 书").font(.system(size:11,weight:.medium)).tracking(2).foregroundStyle(green.opacity(0.65))
                        Text("林间小屋").font(.system(size:34,weight:.light,design:.serif)).tracking(5).foregroundStyle(green)
                    }
                    Spacer()
                    VStack(alignment:.trailing,spacing:7) {
                        Text("第一章 · 遇见").font(.system(size:12,weight:.medium)).foregroundStyle(green.opacity(0.7))
                        HStack(spacing:6) {
                            Circle().fill(model.active ? Color(nsColor:NSColor(hex:0x9AA576)) : Color.gray).frame(width:5,height:5)
                            Text(model.followsLid ? "屏幕 \(model.angleText)" : "手动预览")
                        }.font(.system(size:11,design:.monospaced)).foregroundStyle(green.opacity(0.65))
                    }.padding(.top,8)
                }.padding(.horizontal,42).padding(.top,32).padding(.bottom,4)
                ZStack(alignment:.bottom) {
                    ForestSceneView(model:model)
                    VStack(spacing:7) {
                        Text(model.caption).font(.system(size:15,weight:.regular,design:.serif)).foregroundStyle(green)
                        Text("轻轻开合，故事就会发生。").font(.system(size:11)).foregroundStyle(green.opacity(0.55))
                    }.padding(.bottom,13).allowsHitTesting(false)
                }.frame(maxWidth:.infinity,maxHeight:.infinity)
                if model.controlsVisible {
                    VStack(spacing:13) {
                        HStack(spacing:18) {
                            Label("展开",systemImage:"book.closed").font(.system(size:12))
                            Slider(value:Binding(get:{model.followsLid ? model.progress : model.manual},set:{model.manual=$0}),in:0...1).disabled(model.followsLid).tint(green)
                                .accessibilityLabel("手动展开进度")
                            Text("\(Int(model.progress*100))%").font(.system(size:12,design:.monospaced)).frame(width:42,alignment:.trailing)
                            Divider().frame(height:18)
                            Toggle("跟随屏幕",isOn:$model.followsLid).toggleStyle(.switch).controlSize(.small).font(.system(size:12))
                        }
                        HStack(spacing:15) {
                            Text(model.notice).font(.system(size:11)).foregroundStyle(green.opacity(0.62)).lineLimit(2)
                            Spacer(minLength:4)
                            Button("校准展开位置") { model.calibrate() }.disabled(!model.followsLid || model.state.angle == nil)
                                .help("在80°至120°范围，将当前屏幕角度设为完全展开")
                            Button { model.sound.toggle() } label:{ Image(systemName:model.sound ? "speaker.wave.2" : "speaker.slash") }.help(model.sound ? "关闭声音" : "打开声音")
                                .accessibilityLabel(model.sound ? "关闭声音" : "打开声音")
                            Button { (NSApp.keyWindow ?? NSApp.windows.first(where: { $0.title == "林间小屋" }))?.toggleFullScreen(nil) } label:{ Image(systemName:"arrow.up.left.and.arrow.down.right") }.help("切换全屏")
                            Button { model.controlsVisible=false } label:{ Image(systemName:"chevron.down") }.help("收起控制条")
                        }.buttonStyle(.borderless).font(.system(size:11))
                    }.padding(.horizontal,26).padding(.vertical,17)
                        .background(.regularMaterial,in:RoundedRectangle(cornerRadius:18))
                        .overlay(RoundedRectangle(cornerRadius:18).stroke(green.opacity(0.08),lineWidth:1))
                        .padding(.horizontal,30).padding(.bottom,24).foregroundStyle(green)
                } else {
                    Button("显示控制条") { model.controlsVisible=true }.buttonStyle(.plain).font(.system(size:11)).foregroundStyle(green.opacity(0.65)).padding(.bottom,18)
                }
            }
        }.frame(minWidth:880,minHeight:680)
        .onAppear { DispatchQueue.main.async { model.refreshLifecycle() } }
        .onDisappear { model.stop() }
    }
}
final class ForestDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        sender.activate(ignoringOtherApps: true)
        sender.windows.first(where: { $0.title == "林间小屋" })?.makeKeyAndOrderFront(nil)
        return true
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender:NSApplication)->Bool { true }
}
@main
struct ForestBookApp: App {
    @NSApplicationDelegateAdaptor(ForestDelegate.self) var delegate
    var body: some Scene {
        Window("林间小屋",id:"forest") { ForestBookView() }.defaultSize(width:1120,height:850)
    }
}
