import AppKit
import Combine
import MacPlatform
import PopupBookCore
import PopupBookRuntime

@MainActor final class HostModel: ObservableObject {
    let composition = HostComposition()
    @Published private(set) var state = BookState()
    @Published var controlsVisible = true
    @Published var directory = false
    var selfCheck: HostSelfCheck?
    private var lifecycle: WindowLifecycle?
    private var lastRefresh = 0.0
    var coordinator: BookCoordinator { composition.coordinator }
    var currentTitle: String {
        composition.registry.pages.first(where: { $0.id == state.current })?.title() ?? L10n.text("林间小屋")
    }
    var failed: Bool {
        if let id = state.current, case .failed = state.pageStates[id] { return true }
        return false
    }
    var notice: String {
        if let id = state.current, let message = composition.stateErrors[id] { return message }
        if let notice = state.output.notice { return notice }
        if coordinator.following, coordinator.fold.angle == nil { return L10n.text("铰链角度暂不可用") }
        return coordinator.following ? L10n.text("靠近看它回应，按住缓慢移动来轻抚") : L10n.text("手动预览")
    }
    init() {
        coordinator.onChange = { [weak self] in self?.refresh() }
        coordinator.onPageSelected = { [weak self] id in self?.composition.saveLastPage(id) }
    }
    func attach(_ window: NSWindow) {
        guard lifecycle == nil, selfCheck == nil else { return }
        if composition.preview, ProcessInfo.processInfo.arguments.contains("--self-check") {
            selfCheck = HostSelfCheck(model: self)
            coordinator.setActive(true)
            selfCheck?.start()
            return
        }
        lifecycle = WindowLifecycle { [weak self] active in self?.coordinator.setActive(active) }
        lifecycle?.attach(to: window)
    }
    func refresh() {
        let now = ProcessInfo.processInfo.systemUptime
        let next = coordinator.state
        guard
            now - lastRefresh >= 0.1 || next.phase != state.phase || next.current != state.current
                || next.output.caption != state.output.caption || next.pageStates != state.pageStates
                || next.active != state.active
        else { return }
        lastRefresh = now
        state = next
    }
    func stop() {
        lifecycle?.stop()
        lifecycle = nil
        coordinator.stop()
    }
}
