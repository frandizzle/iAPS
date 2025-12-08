import Foundation

// NOTE: These must be internal because `Suggestion` is internal.
// Do NOT mark these as public.

protocol SuggestionObserver: AnyObject {
    func suggestionDidUpdate(_ suggestion: Suggestion)
}

protocol EnactedSuggestionObserver: AnyObject {
    func enactedSuggestionDidUpdate(_ suggestion: Suggestion)
}
