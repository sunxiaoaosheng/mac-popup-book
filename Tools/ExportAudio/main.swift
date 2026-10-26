import Foundation

let path = CommandLine.arguments.dropFirst().first ?? "build/exported-audio"
do {
    let root = URL(fileURLWithPath: path)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    for (name, seconds, kind) in [("paper", 0.24, 0), ("meow", 0.48, 1), ("forest", 8.0, 2)] {
        try ProceduralAudio.wave(seconds: seconds, kind: kind).write(
            to: root.appendingPathComponent(name + ".wav"))
    }
} catch {
    fputs("音效导出失败：\(error)\n", stderr)
    exit(1)
}
