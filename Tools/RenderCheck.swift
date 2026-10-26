import AppKit
import SceneKit
import Metal

@main
struct RenderCheck {
    static func main() throws {
        _ = NSApplication.shared
        let world = PaperWorld()
        let device = MTLCreateSystemDefaultDevice()!
        let renderer = SCNRenderer(device:device,options:nil)
        renderer.scene = world.scene; renderer.pointOfView = world.camera
        let directory = URL(fileURLWithPath:CommandLine.arguments[1])
        try FileManager.default.createDirectory(at:directory,withIntermediateDirectories:true)
        for (name,p) in [("open",1.0),("half",0.5),("closed",0.03)] {
            var state = BookState(); state.progress=p; state.target=p
            if p > 0.8 { state.outside=1;state.mood = .resting;state.clock=5 }
            world.update(state)
            let image = renderer.snapshot(atTime:0,with:CGSize(width:1600,height:1100),antialiasingMode:.multisampling4X)
            let bitmap = NSBitmapImageRep(data:image.tiffRepresentation!)!
            try bitmap.representation(using:.png,properties:[:])!.write(to:directory.appendingPathComponent("\(name).png"))
            print("渲染：\(name)，\(bitmap.pixelsWide)×\(bitmap.pixelsHigh)")
        }
        world.update({ var s = BookState(); s.outside=1;s.mood = .resting; return s }())
        world.camera.camera?.orthographicScale = 7.0
        let icon = renderer.snapshot(atTime:0,with:CGSize(width:1024,height:1024),antialiasingMode:.multisampling4X)
        let iconBitmap = NSBitmapImageRep(data:icon.tiffRepresentation!)!
        try iconBitmap.representation(using:.png,properties:[:])!.write(to:directory.appendingPathComponent("icon.png"))
        world.camera.camera?.orthographicScale = 6.5
        let first=ProcessInfo.processInfo.systemUptime
        for i in 0..<60 {
            var s = BookState();s.progress=Double(i)/59;s.target=s.progress;world.update(s)
            _ = renderer.snapshot(atTime:Double(i)/60,with:CGSize(width:1120,height:750),antialiasingMode:.multisampling4X)
        }
        let elapsed=ProcessInfo.processInfo.systemUptime-first
        print(String(format:"离屏同步快照60帧：%.2f秒，%.1f帧/秒；非应用实时帧率。",elapsed,60/elapsed))
    }
}
