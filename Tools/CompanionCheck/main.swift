import AppKit
import ForestCabinScene
import MacPlatform
import PaperCatBehavior
import PaperCatRendering
import PopupBookCore
import PopupBookRuntime
import SceneKit
import SceneKitRendering

/// Rendering callbacks are on SceneKit's thread; the summary is read on the main actor.
private final class FrameMetrics: NSObject, SCNSceneRendererDelegate, @unchecked Sendable {
    private let lock = NSLock()
    private var intervals: [Double] = []
    private var previous: Double?
    private var draws = 0
    func renderer(_ renderer: SCNSceneRenderer, updateAtTime time: TimeInterval) {
        lock.lock()
        defer { lock.unlock() }
        if let previous, time > previous, time - previous < 0.5 { intervals.append(time - previous) }
        previous = time
    }
    func renderer(_ renderer: SCNSceneRenderer, didRenderScene scene: SCNScene, atTime time: TimeInterval) {
        lock.lock()
        draws += 1
        lock.unlock()
    }
    func summary() -> (Int, Int, Double, Double) {
        lock.lock()
        defer { lock.unlock() }
        guard !intervals.isEmpty else { return (0, draws, 0, 0) }
        let sorted = intervals.sorted()
        let average = intervals.reduce(0, +) / Double(intervals.count)
        return (
            intervals.count, draws, 1 / average,
            sorted[min(sorted.count - 1, Int(Double(sorted.count) * 0.95))] * 1000
        )
    }
}
@MainActor private final class ManualSource: AngleSource {
    func start(_ callback: @escaping @MainActor (AngleSample) -> Void) { preconditionFailure("此工具不应访问角度硬件") }
    func stop() {}
}
@MainActor private final class QuietSettings: SettingsStore {
    var openAngle = 105.0
    var soundEnabled = false
}
@MainActor private final class AudioLog: AudioOutput {
    var lastError: String?
    var events = 0, loops = 0
    func setActive(_ active: Bool) {}
    func play(_ sound: SoundID) { events += 1 }
    func startLoop(_ sound: SoundID) { loops += 1 }
    func stopLoop(_ sound: SoundID, fade: Double) { loops -= 1 }
}
@MainActor func run() throws {
    let duration = CommandLine.arguments.dropFirst().first.flatMap(Double.init) ?? 30
    guard duration >= 15, duration <= 7200 else { throw CocoaError(.coderInvalidValue) }
    let requestedFPS = CommandLine.arguments.dropFirst(3).first.flatMap(Int.init) ?? 60
    guard (15...120).contains(requestedFPS) else { throw CocoaError(.coderInvalidValue) }
    let directory = URL(fileURLWithPath: CommandLine.arguments.dropFirst(2).first ?? "build/checks/companion")
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let app = NSApplication.shared
    app.setActivationPolicy(.regular)
    let world = ForestCabin()
    let actor = try PaperCatPresenter(stage: world.stage)
    let audio = AudioLog()
    let session = try BookSession(
        character: PaperCat(random: SeededRandom(seed: 20_261_027)), scene: world,
        source: ManualSource(), clock: SystemFrameClock(), settings: QuietSettings(), audio: audio
    ) { pose, context in
        actor.update(pose, in: context)
    }
    let view = BookSceneView(frame: NSRect(x: 0, y: 0, width: 1120, height: 750))
    view.configure(world.stage)
    view.preferredFramesPerSecond = requestedFPS
    let metrics = FrameMetrics()
    view.delegate = metrics
    let window = NSWindow(
        contentRect: view.frame, styleMask: [.titled, .closable, .miniaturizable], backing: .buffered,
        defer: false)
    window.title = "林间小屋：受控陪伴与渲染检查"
    window.contentView = view
    // Test window only: keep the measurement surface visible. Production windows remain normal level.
    window.level = .floating
    window.makeKeyAndOrderFront(nil)
    app.finishLaunching()
    app.activate(ignoringOtherApps: true)
    session.setFollowing(false)
    session.setActive(true)
    view.setPaused(false)
    print("开始受控运行 \(Int(duration)) 秒；手动输入、静音、隔离状态，不作用户十分钟主观验收。")
    fflush(stdout)
    let start = ProcessInfo.processInfo.systemUptime
    var stages = Set<Int>()
    var moods = Set<CatMood>()
    var minProgress = 1.0
    var renderingVerified = false
    func capture(_ name: String) {
        let image = view.snapshot()
        guard let tiff = image.tiffRepresentation, let bitmap = NSBitmapImageRep(data: tiff),
            let data = bitmap.representation(using: .png, properties: [:])
        else { return }
        do { try data.write(to: directory.appendingPathComponent(name + ".png")) } catch {
            print("截图失败：\(error)")
        }
    }
    var timer: Timer?
    let update: @MainActor () -> Void = {
        let elapsed = ProcessInfo.processInfo.systemUptime - start
        moods.insert(session.character.pose.mood)
        minProgress = min(minProgress, session.fold.progress)
        if elapsed >= 6 && stages.insert(1).inserted {
            _ = session.interact(with: session.characterID, interaction: .gentleTouch)
        }
        if elapsed >= 7.3 && stages.insert(2).inserted { capture("petting") }
        if elapsed >= 10 && stages.insert(3).inserted {
            _ = session.interact(with: session.characterID, interaction: .invite(.invitation))
        }
        if elapsed >= 12.5 && stages.insert(4).inserted { capture("invited") }
        if elapsed >= duration * 0.5 && stages.insert(5).inserted { session.setManualProgress(0.5) }
        if elapsed >= duration * 0.5 + 1 && stages.insert(6).inserted {
            capture("half")
            session.setManualProgress(1)
        }
        if elapsed >= duration - 1 && stages.insert(7).inserted { capture("final") }
        if elapsed >= duration {
            timer?.invalidate()
            session.stop()
            view.setPaused(true)
            let (frames, draws, fps, p95) = metrics.summary()
            renderingVerified = frames > Int(duration * 10) && draws > Int(duration * 10)
            let text =
                "真实运行秒数：\(elapsed)\n请求帧率：\(requestedFPS)\n更新回调：\(frames)\n绘制提交回调：\(draws)\n渲染更新回调频率Hz（非显示帧率）：\(fps)\n95百分位回调间隔毫秒：\(p95)\n行为种类：\(moods.map(\.rawValue).sorted().joined(separator: ","))\n最低展开进度：\(minProgress)\n持续渲染证据通过：\(renderingVerified)\n说明：交互由代码注入；不是物理鼠标/合页/用户相处验收。\n"
            print(text)
            do {
                try text.write(
                    to: directory.appendingPathComponent("metrics.txt"), atomically: true, encoding: .utf8
                )
            } catch { print("指标写入失败：\(error)") }
            window.orderOut(nil)
            app.stop(nil)
            app.postEvent(
                NSEvent.otherEvent(
                    with: .applicationDefined, location: .zero, modifierFlags: [], timestamp: 0,
                    windowNumber: 0, context: nil, subtype: 0, data1: 0, data2: 0)!, atStart: false)
        }
    }
    timer = Timer(timeInterval: 0.1, repeats: true) { _ in
        MainActor.assumeIsolated { update() }
    }

    if let timer { RunLoop.main.add(timer, forMode: .common) }
    app.run()
    withExtendedLifetime(metrics) {}
    if !renderingVerified {
        throw NSError(
            domain: "CompanionCheck", code: 2,
            userInfo: [NSLocalizedDescriptionKey: "窗口未持续绘制，本次不能作为渲染性能通过证据。"])
    }
}
do { try MainActor.assumeIsolated { try run() } } catch {
    fputs("陪伴检查失败：\(error)\n", stderr)
    exit(1)
}
