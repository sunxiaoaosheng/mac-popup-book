import Foundation

var count = 0
func check(_ value: @autoclosure () -> Bool, _ message: String) {
    guard value() else { fatalError("未通过：\(message)") }; count += 1
}
func advance(_ state: inout BookState, seconds: Double) {
    for _ in 0..<Int(seconds*120) { state.step(1.0/120) }
}
check(BookState.openness(angle:35) == 0,"收合端点")
check(BookState.openness(angle:105) == 1,"展开端点")
check(BookState.openness(angle:70) == 0.5,"线性中点")
check(BookState.openness(angle:0) == 0,"正常低角钳制")
check(BookState.openness(angle:180) == 1,"正常高角钳制")
check(BookState.openness(angle:.nan) == nil,"非数输入")
check(BookState.openness(angle:.infinity) == nil,"无限输入")
check(BookState.openness(angle: -1) == nil,"非法负角")
check(BookState.openness(angle:90,full:35) == nil,"非法校准")
var s = BookState()
check(!s.calibrate(79),"拒绝低于校准范围")
check(s.calibrate(120),"允许上限校准")
check(s.calibrate(80),"允许下限校准")
check(!s.calibrate(.nan),"校准非数")
s = BookState(); s.progress=0; s.target=1
var prev = 0.0
for _ in 0..<120 { s.step(1.0/120); check(s.progress >= prev && s.progress <= 1,"平滑不超调"); prev = s.progress }
check(s.mood == .stretching,"稳定后伸懒腰")
advance(&s,seconds:4)
check(s.mood == .resting && s.outside == 1,"醒来走出并坐下")
check(s.greet(),"允许点击")
check(!s.greet(),"重复点击不排队")
var meows = 0
for _ in 0..<150 { s.step(1.0/120); if s.didMeow { meows += 1 } }
check(meows == 1,"回应只叫一次")
check(s.mood == .resting,"回应后恢复")
check(s.greet(),"再次回应")
s.target = 0.6; advance(&s,seconds:0.25)
check(s.mood == .returning,"收合打断回应")
let position = s.outside
s.target=1; s.step(1.0/120)
check(abs(s.outside-position) < 0.1,"反向位置连续")
advance(&s,seconds:4); check(s.mood == .resting,"反向重新出门")
for cycle in 0..<10 {
    s.target=0; advance(&s,seconds:1)
    check(s.outside == 0 && s.mood == .sleeping,"第\(cycle+1)次快合完成回屋")
    check(!s.greet(),"收合不可点猫")
    s.target=1; advance(&s,seconds:5)
    check(s.mood == .resting && s.outside == 1,"第\(cycle+1)次展开正常")
}
s = BookState(); s.receive(90,at:0); let old=s.target
s.receive(nil,at:0.1); check(s.sensorAvailable,"瞬时失败保留连接")
s.receive(nil,at:1.2); check(!s.sensorAvailable && s.target==old,"失败后冻结目标")
s.receive(70,at:1.3); check(s.sensorAvailable && s.target==0.5,"连接恢复")
let before=s.progress; s.step(1.0/120); check(abs(s.progress-before)<0.1,"恢复平滑")
check(LidInput.decode([1,103,0]) == 103,"传感器报告")
check(LidInput.decode([1,0]) == nil,"截短报告")
check(LidInput.decode([2,90,0]) == nil,"错误报告编号")
check(LidInput.decode([1,255,255]) == nil,"非法角度报告")
s = BookState(); s.progress=0.9;s.target=0.9
advance(&s,seconds:6);check(abs(s.progress-0.9)<0.001,"静止保持纸机关位置")
print("通过 \(count) 项检查：角度映射、校准、平滑、猫动作、重复点击、快速收合、反向、十次循环、传感器失败恢复。")
if CommandLine.arguments.contains("--sensor") {
    let sensor = LidInput(); var received = false
    sensor.start { angle in if !received { print("真实角度：\(angle.map{String($0)} ?? "不可用")"); received = true } }
    RunLoop.main.run(until:Date(timeIntervalSinceNow:0.8)); sensor.stop()
}
