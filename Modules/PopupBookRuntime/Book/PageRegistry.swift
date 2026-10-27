import Foundation
import PopupBookCore

public struct PageRegistry {
    public private(set) var pages: [PageDescriptor] = []
    public private(set) var errors: [String: String] = [:]
    public init(descriptors: [Data], published: [String]) {
        var discovered: [String: PageDescriptor] = [:]
        var duplicates: Set<String> = []
        for (index, data) in descriptors.enumerated() {
            do {
                let page = try JSONDecoder().decode(PageDescriptor.self, from: data)
                try page.validate()
                if discovered[page.id] != nil {
                    duplicates.insert(page.id)
                    errors[page.id] = "duplicate"
                } else {
                    discovered[page.id] = page
                }
            } catch { errors["descriptor-\(index)"] = String(describing: error) }
        }
        var seen: Set<String> = []
        for id in published where seen.insert(id).inserted {
            if let page = discovered[id], !duplicates.contains(id) {
                pages.append(page)
            } else {
                errors[id] = "unavailable"
            }
        }
    }
}
public enum PageProcessState: Equatable {
    case stopped, starting, ready, running, paused
    case failed(PageError)
}
public enum PageTurnPhase: Equatable { case idle, preparing, collapsing, turning, expanding }
public struct BookState {
    public init() {}
    public var current: String?
    public var target: String?
    public var phase: PageTurnPhase = .idle
    public var progress = 1.0
    public var active = false
    public var pageStates: [String: PageProcessState] = [:]
    public var output = PagePresentation()
    public var turnProgress = 0.0
}
@MainActor public protocol PageProcessPort: AnyObject {
    var onReady: (() -> Void)? { get set }
    var onFrame: ((PagePresentation) -> Void)? { get set }
    var onFailure: ((PageError) -> Void)? { get set }
    func start(epoch: Int)
    func advance(_ context: WorldContext)
    func handle(_ input: PageInput)
    func pause()
    func stop()
}
