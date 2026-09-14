//
//  Spellcheck.swift
//  MonkeyNote
//
//  Underline misspelled words using the SAME language as autocomplete
//  (single source of truth: WordSuggestionManager.dictionaryLanguage).
//  Native NSTextView continuous checking — no manual word scan.
//

#if os(macOS)
import AppKit

extension CursorTextView {

    /// Apply spellcheck state: toggle from UserDefaults, language shared with autocomplete.
    /// Cheap guards make it safe to call on every updateNSView.
    func applySpellcheckSettings() {
        let enabled = UserDefaults.standard.object(forKey: "note.spellcheckEnabled") as? Bool ?? true
        if isContinuousSpellCheckingEnabled != enabled {
            isContinuousSpellCheckingEnabled = enabled
        }
        guard enabled else { return }

        let language = WordSuggestionManager.shared.getDictionaryLanguage()
        let checker = NSSpellChecker.shared
        // setLanguage is app-global; autocomplete passes language per-call so no conflict.
        if checker.language() != language, checker.setLanguage(language) {
            // Language changed -> recheck visible text with the new dictionary.
            isContinuousSpellCheckingEnabled = false
            isContinuousSpellCheckingEnabled = true
        }
    }
}
#endif
