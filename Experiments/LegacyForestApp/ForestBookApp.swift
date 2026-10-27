import MacPlatform
import PopupBookCore
import SwiftUI

@main
struct ForestBookApp: App {
    private let composition: Result<ForestComposition, Error> = Result {
        guard let resources = Bundle.main.resourceURL else { throw CocoaError(.fileNoSuchFile) }
        return try ForestComposition(resources: resources, settings: UserSettings())
    }
    @NSApplicationDelegateAdaptor(ForestDelegate.self) var delegate
    var body: some Scene {
        Window(L10n.text("林间小屋"), id: "forest") {
            switch composition {
            case .success(let composition): ForestBookView(composition: composition)
            case .failure(let error):
                VStack(spacing: 16) {
                    Text(L10n.text("林间小屋暂时无法打开")).font(.title2)
                    Text(error.localizedDescription).textSelection(.enabled)
                }.padding(40)
            }
        }.defaultSize(width: 1440, height: 960).windowStyle(.hiddenTitleBar)
            .commands {
                CommandMenu(L10n.text("互动")) {
                    if case .success(let composition) = composition {
                        Button(L10n.text("轻轻摸摸")) {
                            _ = composition.session.interact(
                                with: composition.session.characterID, interaction: .gentleTouch)
                        }.keyboardShortcut("m", modifiers: [.option])
                        Button(L10n.text("邀请靠近")) {
                            _ = composition.session.interact(
                                with: composition.session.characterID, interaction: .invite(.invitation))
                        }.keyboardShortcut("i", modifiers: [.option])
                    }
                }
            }
    }
}
