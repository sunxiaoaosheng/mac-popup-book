import AppKit
import ForestCabinScene
import MacPlatform
import PaperCatBehavior
import PaperCatRendering
import PopupBookCore
import PopupBookRuntime
import SceneKit
import SceneKitRendering

@MainActor private final class MemorySettings: SettingsStore {
    var openAngle = 105.0
    var soundEnabled = false
}
@MainActor private final class SilentAudio: AudioOutput {
    var lastError: String? { nil }
    func setActive(_ active: Bool) {}
    func play(_ sound: SoundID) {}
}
@MainActor func run() throws {
    let app = NSApplication.shared
    app.setActivationPolicy(.regular)
    let world = ForestCabin()
    let presenter = try PaperCatPresenter(stage: world.stage)
    let session = try BookSession(
        character: PaperCat(), scene: world, source: LidAngleSource(), clock: SystemFrameClock(),
        settings: MemorySettings(), audio: SilentAudio()
    ) { pose, c in presenter.update(pose, in: c) }
    let w = NSWindow(
        contentRect: NSRect(x: 100, y: 100, width: 1120, height: 750),
        styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
    w.title = "林间小屋集成检查"
    let view = BookSceneView(frame: NSRect(x: 0, y: 0, width: 1120, height: 750))
    view.configure(world.stage)
    view.hits.register(presenter.cat, as: session.character.id)
    view.onInteraction = { id, event in session.interact(with: id, interaction: event) }
    session.onChange = { view.setPaused(!session.active) }
    var applicationActive = true
    let lifecycle = WindowLifecycle(
        applicationIsActive: { applicationActive }, onActive: { session.setActive($0) })
    print("本检查使用真实窗口与传感器，应用活动状态通过可控输入模拟，不作为真实前后台焦点验收。")
    w.contentView = view
    w.makeKeyAndOrderFront(nil)
    app.finishLaunching()
    app.activate(ignoringOtherApps: true)
    lifecycle.attach(to: w)
    func later(_ delay: Double, _ block: @escaping @MainActor () -> Void) {
        let t = Timer(timeInterval: delay, repeats: false) { _ in MainActor.assumeIsolated { block() } }
        RunLoop.main.add(t, forMode: .common)
    }
    later(0.5) {
        lifecycle.refresh()
        precondition(session.active, "模拟前台事件应启动会话")
    }
    later(2) {
        print("真实传感器：\(session.fold.angle.map{String($0)} ?? "不可用")°；连接=\(session.fold.sensorAvailable)")
        session.setFollowing(false)
        session.setManualProgress(1)
    }
    later(8) {
        precondition(session.character.pose.mood == .resting, "实际计时器应完成角色出屋")
        let point = view.projectPoint(presenter.cat.convertPosition(SCNVector3(-0.04, 0.84, 0.08), to: nil))
        precondition(view.respond(at: NSPoint(x: point.x, y: point.y)), "实际角色几何命中")
        precondition(session.character.pose.mood == .greeting, "命中后进入回应")
        applicationActive = false
        NotificationCenter.default.post(name: NSApplication.didResignActiveNotification, object: nil)
        precondition(!session.active, "模拟后台暂停")
        applicationActive = true
        NotificationCenter.default.post(name: NSApplication.didBecomeActiveNotification, object: nil)
        precondition(session.active, "模拟前台恢复")
        let other = NSWindow(contentRect: .zero, styleMask: .titled, backing: .buffered, defer: false)
        NotificationCenter.default.post(name: NSWindow.didMiniaturizeNotification, object: other)
        precondition(session.active, "其他窗口不应影响本会话")
        NotificationCenter.default.post(name: NSWindow.didMiniaturizeNotification, object: w)
        precondition(!session.active && !view.isPlaying, "本窗口最小化暂停")
        let frozen = session.context.clock
        later(0.3) {
            precondition(session.context.clock == frozen, "暂停不推进故事")
            NotificationCenter.default.post(name: NSWindow.didDeminiaturizeNotification, object: w)
            precondition(session.active && view.isPlaying, "恢复渲染")
            NSWorkspace.shared.notificationCenter.post(name: NSWorkspace.willSleepNotification, object: nil)
            precondition(!session.active, "模拟睡眠暂停")
            NSWorkspace.shared.notificationCenter.post(name: NSWorkspace.didWakeNotification, object: nil)
            precondition(session.active, "模拟唤醒恢复")
            lifecycle.stop()
            session.stop()
            w.orderOut(nil)
            print("通过：窗口计时器、角色命中、窗口隔离、模拟最小化及睡眠恢复。非物理合盖或鼠标点击记录。")
            app.stop(nil)
            app.postEvent(
                NSEvent.otherEvent(
                    with: .applicationDefined, location: .zero, modifierFlags: [], timestamp: 0,
                    windowNumber: 0, context: nil, subtype: 0, data1: 0, data2: 0)!, atStart: false)
        }
    }
    app.run()
}
do { try MainActor.assumeIsolated { try run() } } catch {
    fputs("窗口检查失败：\(error)\n", stderr)
    exit(1)
}
