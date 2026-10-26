import AppKit
import SceneKit
import Combine

final class BookModel: ObservableObject {
    let world = PaperWorld()
    let sensor = LidInput()
    let audio = BookAudio()
    var state = BookState()
    @Published var followsLid = true { didSet { configureInput() } }
    @Published var manual = 1.0 { didSet { if !followsLid { state.target = manual } } }
    @Published var sound = false { didSet { UserDefaults.standard.set(sound,forKey:"forest.sound"); audio.setActive(sound && active) } }
    @Published var controlsVisible = true
    @Published private(set) var caption = "打开一页，遇见一座森林。"
    @Published private(set) var progress = 1.0
    @Published private(set) var angleText = "连接中"
    @Published private(set) var notice = ""
    @Published private(set) var active = false
    @Published private(set) var renderedFPS = 0
    var pauseRendering: ((Bool) -> Void)?
    var updateAccessibility: ((String) -> Void)?
    private var timer: Timer?
    private var observers: [NSObjectProtocol] = []
    private var lastTick = ProcessInfo.processInfo.systemUptime
    private var uiTick = 0.0
    private var transientNoticeUntil = 0.0
    private var generation = 0
    private var sleeping = false
    private var minimized = false
    private var lastReadingTime = 0.0
    private var renderFrames = 0
    private var renderStart = 0.0
    private let frameLock = NSLock()

    init() {
        let saved = UserDefaults.standard.double(forKey:"forest.openAngle")
        if (80...120).contains(saved) { state.openAngle = saved }
        sound = UserDefaults.standard.bool(forKey:"forest.sound")
        for name in [NSApplication.didBecomeActiveNotification, NSApplication.didResignActiveNotification] {
            observers.append(NotificationCenter.default.addObserver(forName:name,object:nil,queue:.main) { [weak self] _ in self?.refreshLifecycle() })
        }
        observers.append(NotificationCenter.default.addObserver(forName:NSWindow.didMiniaturizeNotification,object:nil,queue:.main) { [weak self] n in
            guard let w = n.object as? NSWindow, w.title == "林间小屋" else { return }
            self?.minimized = true; self?.refreshLifecycle()
        })
        observers.append(NotificationCenter.default.addObserver(forName:NSWindow.didDeminiaturizeNotification,object:nil,queue:.main) { [weak self] n in
            guard let w = n.object as? NSWindow, w.title == "林间小屋" else { return }
            self?.minimized = false; self?.refreshLifecycle()
        })
        observers.append(NSWorkspace.shared.notificationCenter.addObserver(forName:NSWorkspace.willSleepNotification,object:nil,queue:.main) { [weak self] _ in self?.sleeping = true; self?.refreshLifecycle() })
        observers.append(NSWorkspace.shared.notificationCenter.addObserver(forName:NSWorkspace.didWakeNotification,object:nil,queue:.main) { [weak self] _ in self?.sleeping = false; self?.refreshLifecycle() })
    }
    func refreshLifecycle() {
        let shouldRun = NSApp.isActive && !sleeping && !minimized
        guard shouldRun != active else { return }
        active = shouldRun
        if !active { updateAccessibility?("纸雕森林已暂停，等待回到前台。") }
        timer?.invalidate(); timer = nil
        configureInput(); pauseRendering?(!active); audio.setActive(sound && active)
        if active {
            lastTick = ProcessInfo.processInfo.systemUptime; lastReadingTime = lastTick
            let t = Timer(timeInterval:1.0/60,repeats:true) { [weak self] _ in self?.tick() }
            RunLoop.main.add(t,forMode:.common); timer = t
        } else { renderedFPS = 0 }
    }
    private func configureInput() {
        generation += 1; let expected = generation
        sensor.stop()
        if followsLid && active {
            notice = "正在读取屏幕角度…"; lastReadingTime = ProcessInfo.processInfo.systemUptime
            sensor.start { [weak self] angle in
                DispatchQueue.main.async {
                    guard let self, self.generation == expected, self.active, self.followsLid else { return }
                    self.lastReadingTime = ProcessInfo.processInfo.systemUptime
                    self.state.receive(angle,at:self.lastReadingTime)
                }
            }
        } else if !followsLid { state.target = manual; notice = "拖动进度，让森林慢慢展开。" }
    }
    private func tick() {
        let now = ProcessInfo.processInfo.systemUptime, dt = now-lastTick; lastTick = now
        if followsLid && now-lastReadingTime > 1 { state.receive(nil,at:now-1.1); state.receive(nil,at:now) }
        state.step(dt); world.update(state)
        if sound { if state.didRustle { audio.rustle() }; if state.didMeow { audio.meow() } }
        uiTick += dt
        if uiTick >= 0.1 {
            uiTick = 0; progress = state.progress; caption = state.caption
            updateAccessibility?("纸雕森林。展开进度 \(Int(state.progress*100))%。小猫状态：\(state.mood.label)。当前渲染 \(renderedFPS) 帧每秒。")
            angleText = state.angle.map { "\(Int($0))°" } ?? "未连接"
            if followsLid && now > transientNoticeUntil { notice = state.sensorAvailable ? "让屏幕带着森林展开；停下来，看看小猫。" : "角度暂不可用，画面已保留。可关闭跟随，使用手动预览。" }
        }
    }
    func calibrate() {
        transientNoticeUntil = ProcessInfo.processInfo.systemUptime + 3.0
        guard let angle = state.angle, state.calibrate(angle) else { notice = "请先把屏幕打开至 80°～120°，再校准。"; return }
        UserDefaults.standard.set(state.openAngle,forKey:"forest.openAngle")
        notice = "已将 \(Int(state.openAngle))° 设为展开位置。"
    }
    func greet() { _ = state.greet() }
    func renderFrame(at time: Double) {
        frameLock.lock(); defer { frameLock.unlock() }
        if renderStart == 0 { renderStart = time }; renderFrames += 1
        if time-renderStart >= 1 {
            let fps = Int((Double(renderFrames)/(time-renderStart)).rounded())
            renderFrames = 0; renderStart = time
            DispatchQueue.main.async { [weak self] in if self?.active == true { self?.renderedFPS = fps } }
        }
    }
    func stop() { active=false; timer?.invalidate(); timer=nil; sensor.stop(); audio.setActive(false); pauseRendering?(true) }
}
