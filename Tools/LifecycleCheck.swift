import AppKit
import SceneKit

@main struct LifecycleCheck {
    static func main() {
        let app=NSApplication.shared;app.setActivationPolicy(.regular)
        let w=NSWindow(contentRect:NSRect(x:100,y:100,width:440,height:280),styleMask:[.titled,.closable],backing:.buffered,defer:false)
        w.title="林间小屋生命周期检查";w.makeKeyAndOrderFront(nil)
        let model=BookModel();model.followsLid=false;model.manual=0.52
        app.activate(ignoringOtherApps:true)
        func later(_ delay:Double,_ block:@escaping()->Void) {
            let timer=Timer(timeInterval:delay,repeats:false) { _ in block() };RunLoop.main.add(timer,forMode:.common)
        }
        later(0.3) { model.refreshLifecycle();precondition(model.active,"前台激活") }
        later(1.2) {
            precondition(abs(model.state.progress-0.52)<0.02,"实际计时器到达手动目标")
            NSWorkspace.shared.notificationCenter.post(name:NSWorkspace.willSleepNotification,object:nil)
            precondition(!model.active,"睡眠暂停")
            let frozen=model.state.clock
            later(0.3) {
                precondition(model.state.clock==frozen,"暂停不推进故事")
                NSWorkspace.shared.notificationCenter.post(name:NSWorkspace.didWakeNotification,object:nil)
                precondition(model.active,"唤醒恢复")
                later(0.3) {
                    precondition(model.state.clock>frozen,"恢复后计时器推进")
                    model.stop();print("通过：真实计时器、手动目标、模拟睡眠/唤醒通知、暂停冻结、恢复继续。非物理合盖测试。")
                    w.orderOut(nil);app.stop(nil)
                    app.postEvent(NSEvent.otherEvent(with:.applicationDefined,location:.zero,modifierFlags:[],timestamp:0,windowNumber:0,context:nil,subtype:0,data1:0,data2:0)!,atStart:false)
                }
            }
        }
        app.run()
    }
}
