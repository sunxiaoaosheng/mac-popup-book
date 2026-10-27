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
    weak var canvas: SharedCanvas?
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
    var failureDetails: String {
        guard let id = state.current, case .failed(let error) = state.pageStates[id] else { return "" }
        let key: String
        switch error {
        case .startupTimeout: key = "页面启动超时"
        case .stalled: key = "页面停止响应"
        case .incompatibleContract: key = "页面版本不兼容"
        case .missingResources: key = "页面资源缺失"
        case .invalidMessage: key = "页面返回了无效数据"
        default: key = "页面进程暂不可用"
        }
        return L10n.text(key)
    }
    var notice: String {
        if let message = composition.stateErrors["book"] { return message }
        if let id = state.current, let message = composition.pageError(id) {
            return message
        }
        if let notice = state.output.notice { return notice }
        if coordinator.following, coordinator.fold.angle == nil { return L10n.text("铰链角度暂不可用") }
        return coordinator.following ? L10n.text("靠近看它回应，按住缓慢移动来轻抚") : L10n.text("手动预览")
    }
    init() {
        coordinator.onChange = { [weak self] in self?.refresh() }
        coordinator.onPageSelected = { [weak self] id in self?.composition.saveLastPage(id) }
    }
    func attach(_ window: NSWindow) {
        guard lifecycle == nil else { return }
        lifecycle = WindowLifecycle { [weak self] active in self?.coordinator.setActive(active) }
        lifecycle?.attach(to: window)
    }
    func refresh() {
        let now = ProcessInfo.processInfo.systemUptime
        let next = coordinator.state
        if canvas?.isPaused == next.active { canvas?.isPaused = !next.active }
        guard
            next.phase == .turning || now - lastRefresh >= 0.1 || next.phase != state.phase
                || next.current != state.current
                || next.output.caption != state.output.caption || next.pageStates != state.pageStates
                || next.active != state.active
        else { return }
        lastRefresh = now
        if state != next { state = next }
    }
    func stop() {
        lifecycle?.stop()
        lifecycle = nil
        composition.shutdown()
    }
}
