import Foundation
import PopupBookCore

/// Character-independent UI control port. Typed poses remain inside the generic session/presenter pair.
@MainActor public protocol BookSessionControl: AnyObject {
    var fold: FoldState { get }
    var context: WorldContext { get }
    var characterID: CharacterID { get }
    var characterAccessibility: String { get }
    var active: Bool { get }
    var caption: String { get }
    var notice: String { get }
    var soundEnabled: Bool { get }
    var onChange: (() -> Void)? { get set }
    func setActive(_ value: Bool)
    func setFollowing(_ value: Bool)
    func setManualProgress(_ value: Double)
    func setSound(_ value: Bool)
    @discardableResult func calibrate() -> Bool
    @discardableResult func interact(with id: CharacterID, interaction: CharacterInteraction) -> Bool
    func stop()
}
