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
        // File lớn: continuous spellcheck của AppKit recheck theo từng edit,
        // giữ bật trên doc 40k dòng là lag trực tiếp → tắt, vẫn tôn trọng
        // setting của user khi quay lại file nhỏ (updateNSView gọi mỗi lần).
        if isLargeDocument {
            if isContinuousSpellCheckingEnabled {
                isContinuousSpellCheckingEnabled = false
            }
            return
        }
        // Debounce đang giữ tắt trong lúc burst gõ (file vừa) → đừng bật lại
        // ở đây, vì updateNSView gọi hàm này mỗi render (mỗi keystroke).
        guard spellResumeWork == nil else { return }
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

    /// File vừa (~8k từ): continuous spellcheck recheck mỗi keystroke là lag
    /// trực tiếp trên main. Tắt tạm trong lúc burst gõ, bật lại sau 0.8s idle —
    /// gạch đỏ hiện trễ một nhịp, visual cuối không đổi, setting user giữ nguyên.
    /// File lớn đã tắt hẳn, file nhỏ không đụng.
    func scheduleSpellcheckDebounce() {
        guard isMediumOrLargeDocument, !isLargeDocument else { return }
        guard UserDefaults.standard.object(forKey: "note.spellcheckEnabled") as? Bool ?? true else { return }
        if isContinuousSpellCheckingEnabled {
            isContinuousSpellCheckingEnabled = false
        }
        spellResumeWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.spellResumeWork = nil
            guard UserDefaults.standard.object(forKey: "note.spellcheckEnabled") as? Bool ?? true else { return }
            // Bật lại = 1 lần recheck duy nhất sau khi ngừng gõ (không phải mỗi phím).
            self.isContinuousSpellCheckingEnabled = true
        }
        spellResumeWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8, execute: work)
    }
}
#endif
