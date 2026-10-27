import Foundation

public enum PageContract { public static let version = 1 }
public struct PageAudioAsset: Codable, Equatable, Sendable {
    public var id: String
    public var path: String
    public var volume: Float
    public var loops: Bool
    public var autostart: Bool
}
public struct PageDescriptor: Codable, Equatable, Sendable {
    public var id: String
    public var order: Int
    public var names: [String: String]
    public var contractVersion: Int
    public var service: String
    public var product: String
    public var audio: [PageAudioAsset]
    public func title(languages: [String] = Locale.preferredLanguages) -> String {
        let language =
            Bundle.preferredLocalizations(from: ["en", "zh-Hans"], forPreferences: languages).first ?? "en"
        return names[language] ?? names["en"] ?? id
    }
    public func validate() throws {
        guard !id.isEmpty, id.range(of: "^[a-z][a-z0-9-]{0,63}$", options: .regularExpression) != nil,
            contractVersion == PageContract.version, !service.isEmpty, !product.isEmpty
        else { throw PageError.invalidDescriptor }
        for asset in audio {
            guard !asset.path.hasPrefix("/"), !asset.path.split(separator: "/").contains(".."),
                !asset.id.isEmpty, asset.volume.isFinite, (0...1).contains(asset.volume)
            else { throw PageError.invalidDescriptor }
        }
    }
}
public enum PageError: String, Error, Codable, Sendable {
    case invalidDescriptor, incompatibleContract, unavailable, startupTimeout, stalled, invalidMessage,
        missingResources
}
public struct PageAction: Codable, Equatable, Sendable {
    public var shortcut: String?
    public var id: String
    public var title: String
    public var enabled: Bool
    public init(_ id: String, title: String, enabled: Bool = true, shortcut: String? = nil) {
        self.shortcut = shortcut
        self.id = id
        self.title = title
        self.enabled = enabled
    }
}
public enum PagePointerKind: String, Codable, Sendable { case down, move, drag, up, cancel }
public struct PagePointer: Codable, Sendable {
    public var kind: PagePointerKind
    public var x: Double
    public var y: Double
    public var time: Double
    public init(_ kind: PagePointerKind, x: Double, y: Double, time: Double) {
        self.kind = kind
        self.x = x
        self.y = y
        self.time = time
    }
    public var valid: Bool {
        x.isFinite && y.isFinite && time.isFinite && (0...1).contains(x) && (0...1).contains(y)
    }
}
public enum PageInput: Codable, Sendable {
    case pointer(PagePointer)
    case action(String)
    case cancel
}
public struct PageSound: Codable, Sendable {
    public enum Operation: String, Codable, Sendable { case play, begin, end }
    public var id: String
    public var operation: Operation
    public var fade: Double
    public init(_ id: String, _ operation: Operation, fade: Double = 0) {
        self.id = id
        self.operation = operation
        self.fade = fade
    }
}
public struct PagePresentation: Codable, Sendable {
    public var caption: String
    public var accessibility: String
    public var actions: [PageAction]
    public var sounds: [PageSound]
    public var checkpoint: Data?
    public var canSave: Bool
    public var notice: String?
    public init(
        caption: String = "", accessibility: String = "", actions: [PageAction] = [],
        sounds: [PageSound] = [], checkpoint: Data? = nil, canSave: Bool = true, notice: String? = nil
    ) {
        self.caption = caption
        self.accessibility = accessibility
        self.actions = actions
        self.sounds = sounds
        self.checkpoint = checkpoint
        self.canSave = canSave
        self.notice = notice
    }
}
public struct PageStartup: Codable, Sendable {
    public var epoch: Int
    public var width: Int
    public var height: Int
    public var version: Int
    public var languages: [String]
    public var state: Data?
    public var backup: Data?
    public var date: Date
    public init(
        epoch: Int, width: Int, height: Int, state: Data?, backup: Data?, date: Date = Date(),
        languages: [String] = Locale.preferredLanguages
    ) {
        self.epoch = epoch
        self.width = width
        self.height = height
        self.state = state
        self.backup = backup
        self.date = date
        self.languages = languages
        version = PageContract.version
    }
}
public struct PagePrepared: Codable, Sendable {
    public var epoch: Int
    public var pid: Int32
    public var error: PageError?
    public var detail: String?
    public init(epoch: Int, pid: Int32, error: PageError? = nil, detail: String? = nil) {
        self.epoch = epoch
        self.pid = pid
        self.error = error
        self.detail = detail
    }
}
public struct PageFrameRequest: Codable, Sendable {
    public var epoch: Int
    public var surfaceGeneration: Int
    public var sequence: Int
    public var slot: Int
    public var context: WorldContext
    public init(epoch: Int, surfaceGeneration: Int, sequence: Int, slot: Int, context: WorldContext) {
        self.epoch = epoch
        self.surfaceGeneration = surfaceGeneration
        self.sequence = sequence
        self.slot = slot
        self.context = context
    }
}
public struct PageFrameReply: Codable, Sendable {
    public var request: PageFrameRequest
    public var output: PagePresentation
    public var error: PageError?
    public init(request: PageFrameRequest, output: PagePresentation, error: PageError? = nil) {
        self.request = request
        self.output = output
        self.error = error
    }
}
public struct PageSurfaceRequest: Codable, Sendable {
    public var epoch: Int
    public var generation: Int
    public var width: Int
    public var height: Int
    public init(epoch: Int, generation: Int, width: Int, height: Int) {
        self.epoch = epoch
        self.generation = generation
        self.width = width
        self.height = height
    }
}
public struct PageInputRequest: Codable, Sendable {
    public var epoch: Int
    public var input: PageInput
    public init(epoch: Int, input: PageInput) {
        self.epoch = epoch
        self.input = input
    }
}
