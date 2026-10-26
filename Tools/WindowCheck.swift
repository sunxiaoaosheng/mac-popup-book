import AppKit
import SceneKit
import Darwin

final class FrameCounter: NSObject, SCNSceneRendererDelegate {
    weak var model: BookModel?
    func renderer(_ renderer:SCNSceneRenderer,didRenderScene scene:SCNScene,atTime time:TimeInterval) { model?.renderFrame(at:time) }
}
@main struct WindowCheck {
    static func main() {
        let app = NSApplication.shared
        app.setActivationPolicy(.regular)
        let model = BookModel()
        let w = NSWindow(contentRect:NSRect(x:100,y:100,width:1120,height:750),styleMask:[.titled,.closable,.miniaturizable,.resizable],backing:.buffered,defer:false)
        w.title = "林间小屋"
        let view = PaperView(frame:NSRect(x:0,y:0,width:1120,height:750))
        view.scene = model.world.scene; view.pointOfView = model.world.camera
        view.antialiasingMode = .multisampling4X; view.preferredFramesPerSecond = 60
        view.isPlaying=true;view.rendersContinuously=true
        let counter=FrameCounter();counter.model=model;view.delegate=counter
        view.onCat = { model.greet() }
        model.pauseRendering = { paused in view.isPlaying = !paused;view.rendersContinuously = !paused }
        w.contentView=view;w.makeKeyAndOrderFront(nil);app.activate(ignoringOtherApps:true)
        func later(_ delay:Double,_ block:@escaping ()->Void) {
            let timer=Timer(timeInterval:delay,repeats:false) { _ in block() }
            RunLoop.main.add(timer,forMode:.common)
        }
        later(0.5) {
            model.refreshLifecycle()
            precondition(model.active,"窗口应在前台")
        }
        later(2) {
            print("真实传感器：\(model.state.angle.map{String($0)} ?? "不可用")°；连接=\(model.state.sensorAvailable)")
            model.followsLid=false;model.manual=1
        }
        func usage() -> Double {
            var u = rusage(); getrusage(RUSAGE_SELF,&u)
            return Double(u.ru_utime.tv_sec+u.ru_stime.tv_sec)+Double(u.ru_utime.tv_usec+u.ru_stime.tv_usec)/1_000_000
        }
        var foregroundCPU = 0.0
        later(3) { foregroundCPU = usage() }
        later(8) {
            precondition(model.state.mood == .resting,"真实窗口计时器应完成出屋")
            precondition(model.renderedFPS > 0,"必须确实绘制过帧")
            print(String(format:"前台5秒进程CPU均值：%.1f%%（100%%约为一个CPU核心）。",(usage()-foregroundCPU)/5*100))
            print("真实窗口实时渲染：\(model.renderedFPS) 帧/秒（1120×750逻辑点，4倍多重采样）。")
            guard let node=model.world.scene.rootNode.childNode(withName:"cat",recursively:true) else { fatalError("猫节点缺失") }
            let point=view.projectPoint(node.convertPosition(SCNVector3(-0.04,0.84,0.08),to:nil))
            view.respondToCat(at:NSPoint(x:point.x,y:point.y))
            precondition(model.state.mood == .greeting,"场景命中应触发抬爪回应")
            print("通过：真实场景几何命中、点击回调与抬爪状态。不是物理鼠标点击记录。")
            NotificationCenter.default.post(name:NSWindow.didMiniaturizeNotification,object:w)
            precondition(!model.active && !view.isPlaying && !view.rendersContinuously,"最小化应停止渲染")
            let t=model.state.clock
            later(0.3) {
                precondition(model.state.clock==t,"暂停后时间冻结")
                NotificationCenter.default.post(name:NSWindow.didDeminiaturizeNotification,object:w)
                precondition(model.active && view.isPlaying,"恢复应重新渲染")
                print("通过：渲染开关与生命周期联动。")
                NSWorkspace.shared.notificationCenter.post(name:NSWorkspace.willSleepNotification,object:nil)
                precondition(!model.active && !view.isPlaying,"睡眠通知应暂停")
                let frozen=model.state.clock, cpu=usage()
                later(2) {
                    precondition(model.state.clock==frozen,"暂停后时间冻结")
                    print(String(format:"模拟睡眠暂停2秒进程CPU均值：%.2f%%。",(usage()-cpu)/2*100))
                    NSWorkspace.shared.notificationCenter.post(name:NSWorkspace.didWakeNotification,object:nil)
                    precondition(model.active && view.isPlaying,"唤醒通知应恢复")
                    print("通过：模拟睡眠与唤醒；不等于物理合盖测试。")
                    model.stop();w.orderOut(nil);app.stop(nil)
                    app.postEvent(NSEvent.otherEvent(with:.applicationDefined,location:.zero,modifierFlags:[],timestamp:0,windowNumber:0,context:nil,subtype:0,data1:0,data2:0)!,atStart:false)
                }
            }
        }
        app.run()
        _ = counter
    }
}
