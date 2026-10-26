import MacPlatform
import SwiftUI

@main
struct ForestBookApp: App {
    private let composition: Result<ForestComposition, Error> = Result {
        guard let resources = Bundle.main.resourceURL else { throw CocoaError(.fileNoSuchFile) }
        return try ForestComposition(resources: resources, settings: UserSettings())
    }
    @NSApplicationDelegateAdaptor(ForestDelegate.self) var delegate
    var body: some Scene {
        Window("林间小屋", id: "forest") {
            switch composition {
            case .success(let composition): ForestBookView(composition: composition)
            case .failure(let error):
                VStack(spacing: 16) {
                    Text("林间小屋暂时无法打开").font(.title2)
                    Text(error.localizedDescription).textSelection(.enabled)
                }.padding(40)
            }
        }.defaultSize(width: 1120, height: 850)
    }
}
