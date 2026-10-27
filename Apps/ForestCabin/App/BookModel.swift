import AppKit
import Combine
import MacPlatform
import PopupBookCore
import PopupBookRuntime

@MainActor final class BookModel: ObservableObject {
    let composition: ForestComposition
    var session: any BookSessionControl { composition.session }
    @Published var followsLid = true { didSet { session.setFollowing(followsLid) } }
    @Published var manual = 1.0 { didSet { session.setManualProgress(manual) } }
    @Published var sound: Bool { didSet { session.setSound(sound) } }
    @Published var controlsVisible = true
    @Published private(set) var caption: String
    @Published private(set) var progress = 1.0
    @Published private(set) var angleText = L10n.text("连接中")
    @Published private(set) var notice = ""
    @Published private(set) var active = false
    @Published private(set) var renderedFPS = 0
    private var lastUIRefresh = -1.0
    private(set) var sceneView: BookSceneViewReference?
    private var lifecycle: WindowLifecycle?
    init(composition: ForestComposition) {
        self.composition = composition
        sound = composition.session.soundEnabled
        caption = composition.session.caption
        session.onChange = { [weak self] in self?.refresh() }
    }
    func attach(view: BookSceneViewReference, window: NSWindow) {
        sceneView = view
        lifecycle?.stop()
        lifecycle = WindowLifecycle { [weak self] active in self?.session.setActive(active) }
        lifecycle?.attach(to: window)
        refresh(force: true)
    }
    private func refresh(force: Bool = false) {
        if force || session.active != active { sceneView?.pause(!session.active) }
        let time = session.context.clock
        guard
            force || session.active != active || time - lastUIRefresh >= 0.1 || notice != session.notice
                || caption != session.caption
        else { return }
        lastUIRefresh = time
        if active != session.active { active = session.active }
        if caption != session.caption { caption = session.caption }
        if progress != session.fold.progress { progress = session.fold.progress }
        if notice != session.notice { notice = session.notice }
        let nextAngleText =
            session.fold.angle.map { L10n.text("铰链 %@°", String(Int($0))) } ?? L10n.text("铰链角度暂不可用")
        if angleText != nextAngleText { angleText = nextAngleText }
        sceneView?.accessibility(
            active
                ? L10n.text(
                    "纸雕森林。展开进度 %@%。角色状态：%@。", String(Int(progress * 100)), session.characterAccessibility)
                : L10n.text("纸雕森林已暂停，等待回到前台。"))
    }
    func gentlyTouch() {
        _ = session.interact(with: session.characterID, interaction: .gentleTouch)
        refresh(force: true)
    }
    func inviteCloser() {
        _ = session.interact(with: session.characterID, interaction: .invite(.invitation))
        refresh(force: true)
    }
    func calibrate() {
        session.calibrate()
        refresh(force: true)
    }
    func stop() {
        lifecycle?.stop()
        lifecycle = nil
        session.stop()
        sceneView?.pause(true)
        sceneView = nil
    }
}
/// The view reference uses closures, so UI state does not own an SCNView.
struct BookSceneViewReference {
    let pause: (Bool) -> Void
    let accessibility: (String) -> Void
}
