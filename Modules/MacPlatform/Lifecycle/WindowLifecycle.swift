import AppKit
import PopupBookCore

/// Window identity is injected; notifications for other windows cannot pause this application.
@MainActor public final class WindowLifecycle {
    private let center: NotificationCenter
    private let workspace: NotificationCenter
    private var tokens: [(NotificationCenter, NSObjectProtocol)] = []
    private weak var window: NSWindow?
    private var sleeping = false, minimized = false
    private let applicationIsActive: @MainActor () -> Bool
    private let onActive: (Bool) -> Void
    public init(
        center: NotificationCenter = .default,
        workspace: NotificationCenter = NSWorkspace.shared.notificationCenter,
        applicationIsActive: @escaping @MainActor () -> Bool = { NSApp.isActive },
        onActive: @escaping (Bool) -> Void
    ) {
        self.applicationIsActive = applicationIsActive
        self.center = center
        self.workspace = workspace
        self.onActive = onActive
    }
    public func attach(to window: NSWindow) {
        stop()
        self.window = window
        minimized = window.isMiniaturized
        sleeping = false
        for name in [NSApplication.didBecomeActiveNotification, NSApplication.didResignActiveNotification] {
            observe(center, name) { [weak self] _ in self?.refresh() }
        }
        observe(center, NSWindow.didMiniaturizeNotification) { [weak self] note in
            guard let self, let window = note.object as? NSWindow, window === self.window else { return }
            self.minimized = true
            self.refresh()
        }
        observe(center, NSWindow.didDeminiaturizeNotification) { [weak self] note in
            guard let self, let window = note.object as? NSWindow, window === self.window else { return }
            self.minimized = false
            self.refresh()
        }
        observe(workspace, NSWorkspace.willSleepNotification) { [weak self] _ in
            self?.sleeping = true
            self?.refresh()
        }
        observe(workspace, NSWorkspace.didWakeNotification) { [weak self] _ in
            self?.sleeping = false
            self?.refresh()
        }
        refresh()
    }
    private func observe(
        _ c: NotificationCenter, _ name: Notification.Name,
        _ body: @escaping @MainActor (Notification) -> Void
    ) {
        let token = c.addObserver(forName: name, object: nil, queue: .main) { n in
            MainActor.assumeIsolated { body(n) }
        }
        tokens.append((c, token))
    }
    public func refresh() { onActive(window != nil && applicationIsActive() && !sleeping && !minimized) }
    public func stop() {
        for (c, t) in tokens { c.removeObserver(t) }
        tokens = []
        window = nil
        onActive(false)
    }
    deinit { for (c, t) in tokens { c.removeObserver(t) } }
}
