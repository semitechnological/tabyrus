import XCTest
@testable import Tabyrus

final class SuggestionAcceptanceTests: XCTestCase {
    func test_applyingInsertion_replacesSelection() {
        let text = SuggestionAcceptance.textByApplyingInsertion(
            "world",
            to: "hello there",
            selectedRange: NSRange(location: 6, length: 5)
        )

        XCTAssertEqual(text, "hello world")
    }

    func test_applyingInsertion_appendsWithoutSelectionRange() {
        let text = SuggestionAcceptance.textByApplyingInsertion(
            " world",
            to: "hello",
            selectedRange: nil
        )

        XCTAssertEqual(text, "hello world")
    }
}
