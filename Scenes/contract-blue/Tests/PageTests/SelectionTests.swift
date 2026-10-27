import PageBehavior
import XCTest

final class SelectionTests: XCTestCase {
    func testInvalidAndOutOfBoundsInput() {
        var state = Selection()
        state.select(2)
        XCTAssertEqual(state.value, 1)
        state.select(.nan)
        XCTAssertEqual(state.value, 1)
        state.select(-1)
        XCTAssertEqual(state.value, 0)
    }
}
