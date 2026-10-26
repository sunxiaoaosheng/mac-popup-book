import Foundation

@MainActor public protocol AngleSource: AnyObject {
    func start(_ onSample: @escaping @MainActor (AngleSample) -> Void)
    func stop()
}
