import SceneKitRendering
import SwiftUI

struct ForestBookView: View {
    @StateObject private var model: BookModel
    init(composition: ForestComposition) {
        _model = StateObject(wrappedValue: BookModel(composition: composition))
    }
    private let green = Color(nsColor: NSColor(hex: 0x405843))
    var body: some View {
        ZStack {
            ForestSceneView(model: model)
                .frame(maxWidth: .infinity, maxHeight: .infinity).ignoresSafeArea()
            VStack {
                if model.controlsVisible {
                    HStack(spacing: 12) {
                        Text(L10n.text("林间小屋")).font(.system(size: 20, weight: .medium, design: .serif))
                        Text(model.followsLid ? model.angleText : L10n.text("手动预览"))
                            .font(.system(size: 12, design: .monospaced))
                        if !model.active { Text(L10n.text("已暂停")).font(.system(size: 12)) }
                        Spacer()
                    }
                    .padding(12).background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
                    .padding(.horizontal, 24).padding(.top, 16)
                }
                Spacer(minLength: 0)
                if model.controlsVisible {
                    Text(model.caption).font(.system(size: 18, weight: .medium, design: .serif))
                        .padding(.horizontal, 18).padding(.vertical, 9)
                        .background(.regularMaterial, in: Capsule()).allowsHitTesting(false)
                    controls.padding(.horizontal, 24).padding(.bottom, 18)
                } else {
                    HStack {
                        Spacer()
                        Button(L10n.text("显示控制条")) { model.controlsVisible = true }
                            .buttonStyle(.bordered).padding(8)
                            .background(.regularMaterial, in: Capsule())
                    }.padding(18)
                }
            }
        }
        .foregroundStyle(green).frame(minWidth: 880, minHeight: 680)
        .onDisappear { model.stop() }
    }
    private var controls: some View {
        VStack(spacing: 12) {
            HStack(spacing: 14) {
                Button(L10n.text("轻轻摸摸")) { model.gentlyTouch() }
                    .disabled(!model.active)
                Button(L10n.text("邀请靠近")) { model.inviteCloser() }
                    .disabled(!model.active)
                Text(L10n.text("靠近看它回应，按住缓慢移动来轻抚"))
                    .font(.system(size: 12)).foregroundStyle(green.opacity(0.8))
                    .lineLimit(2).frame(maxWidth: 420, alignment: .leading).layoutPriority(-1)
                Spacer(minLength: 0)
                Button {
                    model.sound.toggle()
                } label: {
                    Label(
                        model.sound ? L10n.text("声音已开") : L10n.text("声音已关"),
                        systemImage: model.sound ? "speaker.wave.2" : "speaker.slash")
                }.accessibilityLabel(model.sound ? L10n.text("关闭声音") : L10n.text("打开声音"))
                Button {
                    model.controlsVisible = false
                } label: {
                    Label(L10n.text("收起"), systemImage: "chevron.down")
                }
            }.buttonStyle(.bordered).controlSize(.regular)
            HStack(spacing: 14) {
                Label(L10n.text("展开"), systemImage: "book.closed").font(.system(size: 12))
                Slider(
                    value: Binding(
                        get: { model.followsLid ? model.progress : model.manual },
                        set: { model.manual = $0 }), in: 0...1
                )
                .disabled(model.followsLid).tint(green).accessibilityLabel(L10n.text("手动展开进度"))
                Text("\(Int(model.progress * 100))%")
                    .font(.system(size: 12, design: .monospaced)).frame(width: 42)
                Toggle(L10n.text("跟随屏幕"), isOn: $model.followsLid).toggleStyle(.switch).controlSize(.small)
                Button(L10n.text("校准")) { model.calibrate() }
                    .disabled(!model.followsLid || model.session.fold.angle == nil)
            }
            Text(model.notice.isEmpty ? " " : model.notice)
                .font(.system(size: 12)).lineLimit(2)
                .frame(maxWidth: .infinity, minHeight: 32, maxHeight: 32, alignment: .leading)
                .accessibilityHidden(model.notice.isEmpty)
        }
        .padding(16).background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18))
    }
}
