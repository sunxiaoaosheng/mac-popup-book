import Darwin
import Foundation

/// Shared by host-created connections, never global. Serializes reuse of a bundled service after exit.
@MainActor public final class PageProcessSupervisor {
    struct Identity: Equatable {
        let pid: Int32
        let path: String
        let seconds: UInt64
        let microseconds: UInt64
    }
    private var known: [String: Identity] = [:]
    private var retiring: [String: Identity] = [:]
    public init() {}
    func identity(_ pid: Int32, expectedPath: String) -> Identity? {
        guard pid > 0 else { return nil }
        var path = [CChar](repeating: 0, count: 4096)
        guard proc_pidpath(pid, &path, UInt32(path.count)) > 0, String(cString: path) == expectedPath else {
            return nil
        }
        var info = proc_bsdinfo()
        guard
            proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &info, Int32(MemoryLayout<proc_bsdinfo>.size))
                == MemoryLayout<proc_bsdinfo>.size
        else { return nil }
        return Identity(
            pid: pid, path: expectedPath, seconds: info.pbi_start_tvsec, microseconds: info.pbi_start_tvusec)
    }
    func register(_ service: String, identity: Identity) { known[service] = identity }
    public func shutdown() {
        for worker in known.values { terminate(worker) }
        known = [:]
        retiring = [:]
    }
    func retire(_ service: String, identity: Identity) { retiring[service] = identity }
    func terminate(_ worker: Identity) {
        if identity(worker.pid, expectedPath: worker.path) == worker { kill(worker.pid, SIGKILL) }
    }
    func whenAvailable(_ service: String, wanted: @escaping () -> Bool, perform: @escaping () -> Void) {
        guard wanted() else { return }
        if let old = retiring[service], identity(old.pid, expectedPath: old.path) == old {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [self] in
                whenAvailable(service, wanted: wanted, perform: perform)
            }
        } else {
            retiring[service] = nil
            perform()
        }
    }
}
