import Foundation
@main struct ExportAudio {
    static func main() throws {
        let root = URL(fileURLWithPath:CommandLine.arguments[1])
        try FileManager.default.createDirectory(at:root,withIntermediateDirectories:true)
        for (name,seconds,kind) in [("paper",0.24,0),("meow",0.48,1),("forest",8.0,2)] {
            try BookAudio.wave(seconds:seconds,kind:kind).write(to:root.appendingPathComponent("\(name).wav"))
        }
        print("已导出三段原创合成音效。")
    }
}
