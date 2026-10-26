import Foundation
import IOKit.hid
import PopupBookCore

/// Serial ownership: HID creation, reads, and close all run on the same background queue.
private final class HIDReader {
    private let queue = DispatchQueue(label: "local.forestbook.lid", qos: .userInitiated)
    private var timer: DispatchSourceTimer?
    private var manager: IOHIDManager?
    private var device: IOHIDDevice?
    private var attempts = 0
    private var onReading: ((Double?) -> Void)?
    func start(_ callback: @escaping (Double?) -> Void) {
        queue.async { [weak self] in
            guard let self, self.timer == nil else { return }
            self.onReading = callback
            let timer = DispatchSource.makeTimerSource(queue: self.queue)
            timer.schedule(deadline: .now(), repeating: 1.0 / 30)
            timer.setEventHandler { [weak self] in self?.read() }
            self.timer = timer
            timer.resume()
        }
    }
    func stop() {
        queue.async { [weak self] in
            self?.timer?.cancel()
            self?.timer = nil
            self?.onReading = nil
            self?.close()
        }
    }
    deinit {
        timer?.cancel()
        let device = self.device
        let manager = self.manager
        queue.async {
            if let device { IOHIDDeviceClose(device, 0) }
            if let manager { IOHIDManagerClose(manager, 0) }
        }
    }
    private func close() {
        if let device { IOHIDDeviceClose(device, 0) }
        device = nil
        if let manager { IOHIDManagerClose(manager, 0) }
        manager = nil
    }
    private func connect() {
        close()
        let m = IOHIDManagerCreate(kCFAllocatorDefault, 0)
        // Narrow sensor-only matching: never open keyboard / pointer devices.
        IOHIDManagerSetDeviceMatching(
            m,
            [
                kIOHIDVendorIDKey: 0x05ac,
                kIOHIDDeviceUsagePageKey: 0x20,
                kIOHIDDeviceUsageKey: 0x8a,
            ] as CFDictionary)
        guard IOHIDManagerOpen(m, 0) == kIOReturnSuccess else { return }
        manager = m
        if let devices = IOHIDManagerCopyDevices(m) as? Set<IOHIDDevice> {
            for candidate in devices {
                if IOHIDDeviceOpen(candidate, 0) == kIOReturnSuccess {
                    device = candidate
                    return
                }
            }
        }
    }
    private func read() {
        if device == nil {
            if attempts % 30 == 0 { connect() }
            attempts += 1
        }
        var value: Double?
        if let device {
            var report = [UInt8](repeating: 0, count: 8)
            var length = report.count
            let result = IOHIDDeviceGetReport(device, kIOHIDReportTypeFeature, 1, &report, &length)
            if result == kIOReturnSuccess {
                value = Self.decode(Array(report.prefix(length)))
            } else {
                close()
            }
        }
        onReading?(value)
    }
    static func decode(_ bytes: [UInt8]) -> Double? {
        guard bytes.count >= 3, bytes[0] == 1 else { return nil }
        let angle = Int(bytes[1]) | Int(bytes[2]) << 8
        return (0...180).contains(angle) ? Double(angle) : nil
    }
}

@MainActor public final class LidAngleSource: AngleSource {
    private let reader = HIDReader()
    private var generation = 0
    public init() {}
    public func start(_ onSample: @escaping @MainActor (AngleSample) -> Void) {
        generation += 1
        let token = generation
        reader.start { [weak self] angle in
            let sample = AngleSample(angle: angle, timestamp: ProcessInfo.processInfo.systemUptime)
            DispatchQueue.main.async {
                guard let self, self.generation == token else { return }
                onSample(sample)
            }
        }
    }
    public func stop() {
        generation += 1
        reader.stop()
    }
    public static func decode(_ bytes: [UInt8]) -> Double? { HIDReader.decode(bytes) }
}
