import Foundation

@MainActor public protocol FrameClock: AnyObject {
    var now: TimeInterval { get }
    func start(_ onFrame: @escaping @MainActor (TimeInterval) -> Void)
    func stop()
}
