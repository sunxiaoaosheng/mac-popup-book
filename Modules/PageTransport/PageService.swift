import Foundation
import IOSurface

@objc public protocol PageService {
    func prepare(_ data: Data, reply: @escaping (IOSurface?, IOSurface?, IOSurface?, Data) -> Void)
    func resize(_ data: Data, reply: @escaping (IOSurface?, IOSurface?, IOSurface?, Data) -> Void)
    func render(_ data: Data, reply: @escaping (Data) -> Void)
    func input(_ data: Data)
    func suspend(_ epoch: Int, reply: @escaping (Data?) -> Void)
    func finish(_ epoch: Int, reply: @escaping (Data?) -> Void)
    func injectFault(_ mode: Int)
}
public func pageServiceInterface() -> NSXPCInterface {
    let interface = NSXPCInterface(with: PageService.self)
    for selector in [#selector(PageService.prepare(_:reply:)), #selector(PageService.resize(_:reply:))] {
        for index in 0..<3 {
            interface.setClasses(
                NSSet(object: IOSurface.self) as! Set<AnyHashable>, for: selector, argumentIndex: index,
                ofReply: true)
        }
    }
    return interface
}
