import XCTest
@testable import Tabyrus

final class SuggestionTextNormalizerTests: XCTestCase {
    func test_normalize_removesChatTemplateMarkers() {
        let normalized = SuggestionTextNormalizer.normalize(
            "<|im_start|> useful continuation<|im_end|>"
        )

        XCTAssertEqual(normalized, "useful continuation")
    }

    func test_normalize_removesThinkingBlock() {
        let normalized = SuggestionTextNormalizer.normalize(
            "<think>private reasoning</think> visible answer"
        )

        XCTAssertEqual(normalized, "visible answer")
    }

    func test_formatGhostText_stripsRepeatedPrecedingTail() {
        let formatted = SuggestionTextNormalizer.formatGhostText(
            "world is ready",
            relativeTo: "hello world"
        )

        XCTAssertEqual(formatted, " is ready")
    }

    func test_formatGhostText_stripsExposedSpaceWhenPrefixEndsWithSpace() {
        let formatted = SuggestionTextNormalizer.formatGhostText(
            "world is ready",
            relativeTo: "hello world "
        )

        XCTAssertEqual(formatted, "is ready")
    }
}
