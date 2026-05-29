import Foundation

enum SuggestionAcceptance {
    static func textByApplyingInsertion(_ insertion: String, to currentValue: String, selectedRange: NSRange?) -> String {
        guard let selectedRange,
              let range = Range(selectedRange, in: currentValue) else {
            return currentValue + insertion
        }

        return currentValue.replacingCharacters(in: range, with: insertion)
    }
}
