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
    @Published private(set) var angleText = "连接中"
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
        guard force || session.active != active || time - lastUIRefresh >= 0.1 || notice != session.notice
        else { return }
        lastUIRefresh = time
        active = session.active
        caption = session.caption
        progress = session.fold.progress
        notice = session.notice
        angleText = session.fold.angle.map { "\(Int($0))°" } ?? "未连接"
        sceneView?.accessibility(
            active
                ? "纸雕森林。展开进度 \(Int(progress*100))%。角色状态：\(session.characterAccessibility)。"
                : "纸雕森林已暂停，等待回到前台。")
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
