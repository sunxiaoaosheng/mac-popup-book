import Foundation
import IOSurface

@objc public protocol ProbeService {
    func prepare(
        _ width: Int, height: Int, reply: @escaping (IOSurface?, IOSurface?, IOSurface?, Int32) -> Void)
    func render(_ slot: Int, sequence: Int, value: Double, reply: @escaping (Int, Int) -> Void)
    func fail(_ mode: Int)
}
public func probeInterface() -> NSXPCInterface {
    let interface = NSXPCInterface(with: ProbeService.self)
    for index in 0..<3 {
        interface.setClasses(
            NSSet(object: IOSurface.self) as! Set<AnyHashable>,
            for: #selector(ProbeService.prepare(_:height:reply:)), argumentIndex: index, ofReply: true)
    }
    return interface
}
