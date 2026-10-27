import Foundation

let path = CommandLine.arguments.dropFirst().first ?? "build/exported-audio"
do {
    let root = URL(fileURLWithPath: path)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    for (name, seconds, kind, variant) in [
        ("paper", 0.24, 0, 0), ("paper-soft", 0.28, 0, 1),
        ("meow", 0.48, 1, 0), ("meow-soft", 0.52, 1, 1), ("meow-short", 0.42, 1, 2),
        ("footstep", 0.12, 4, 0), ("footstep-soft", 0.14, 4, 1),
        ("purr", 2.0, 3, 0), ("forest", 8.0, 2, 0),
    ] {
        try ProceduralAudio.wave(seconds: seconds, kind: kind, variant: variant).write(
            to: root.appendingPathComponent(name + ".wav"))
    }
} catch {
    fputs("音效导出失败：\(error)\n", stderr)
    exit(1)
}
