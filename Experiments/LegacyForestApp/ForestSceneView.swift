import AppKit
import SceneKitRendering
import SwiftUI

struct ForestSceneView: NSViewRepresentable {
    let model: BookModel
    final class HostedView: BookSceneView {
        var appeared: ((HostedView, NSWindow) -> Void)?
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if let window { appeared?(self, window) }
        }
    }
    func makeNSView(context: Context) -> HostedView {
        let view = HostedView(frame: .zero)
        model.composition.configure(view)
        view.setAccessibilityElement(true)
        view.setAccessibilityRole(.image)
        view.setAccessibilityLabel(L10n.text("纸雕森林"))
        view.appeared = { [weak model] view, window in
            model?.attach(
                view: BookSceneViewReference(
                    pause: { [weak view] in view?.setPaused($0) },
                    accessibility: { [weak view] in view?.setAccessibilityLabel($0) }), window: window)
        }
        return view
    }
    func updateNSView(_ view: HostedView, context: Context) {}
    static func dismantleNSView(_ view: HostedView, coordinator: ()) {
        view.setPaused(true)
        view.appeared = nil
        view.onInteraction = nil
    }
}
