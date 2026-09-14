//
//  Autocomplete.swift
//  MonkeyNote
//
//  Inline ghost text: the suggestion is inserted into textStorage as gray
//  preview characters, so layout pushes right-side text aside instead of
//  painting over it (fixes mid-text overlap).
//

#if os(macOS)
import AppKit

// MARK: - Autocomplete Inline Ghost Text
extension CursorTextView {

    /// Document text without the ghost preview (for SwiftUI sync compares).
    func stringWithoutGhost() -> String {
        guard let range = ghostRange,
              range.location + range.length <= (string as NSString).length else {
            return string
        }
        return (string as NSString).replacingCharacters(in: range, with: "")
    }

    /// Strip ghost preview before any real edit so the stored range never
    /// goes stale while the edit shifts layout.
    func discardGhostBeforeEdit() {
        if ghostRange != nil {
            clearInlineGhost()
        } else {
            currentSuggestion = nil
        }
    }

    /// Remove ghost chars silently: no undo registration, no document update.
    /// Never deletes blindly — content must still match the suggestion.
    func clearInlineGhost() {
        let range = ghostRange
        let expected = currentSuggestion
        ghostRange = nil
        currentSuggestion = nil
        guard let range, let expected, !expected.isEmpty,
              let ts = textStorage,
              range.location + range.length <= ts.length,
              ts.attributedSubstring(from: range).string == expected else { return }

        isApplyingGhost = true
        undoManager?.disableUndoRegistration()
        ts.deleteCharacters(in: range)
        undoManager?.enableUndoRegistration()
        // Caret was parked at ghost start; clamp it back there — but only for
        // a collapsed caret. Never collapse an active selection (mouse drag /
        // Shift+arrows in any direction) just to drop a ghost preview.
        let cur = selectedRange()
        if cur.length == 0 && cur.location > range.location && cur.location <= range.location + range.length {
            setSelectedRange(NSRange(location: range.location, length: 0))
        }
        isApplyingGhost = false
    }

    func updateSuggestion() {
        // IME compose (Telex/VNI): đừng sờ ghost layer/layout giữa chừng → nhảy caret.
        guard !hasMarkedText() else { return }
        // File lớn: NSSpellChecker.completions chạy sync trên main thread mỗi
        // keystroke → tắt hẳn, gõ mượt quan trọng hơn gợi ý.
        guard !isLargeDocument else {
            hideSuggestion()
            return
        }
        // Check if autocomplete is enabled
        guard autocompleteEnabled else {
            hideSuggestion()
            return
        }

        // Cancel any pending suggestion task
        suggestionTask?.cancel()

        // Drop stale preview immediately (no delay for hiding)
        clearInlineGhost()

        // File vừa (~8k từ): chèn/xóa ghost = 2 storage-edit + layout mỗi phím
        // → debounce 0.12s, gõ burst thì không hiện, dừng lại mới hiện.
        // Visual ghost giữ nguyên, chỉ thêm trễ khi gõ nhanh.
        if isMediumOrLargeDocument, autocompleteDelay <= 0 {
            suggestionTask = Task {
                try? await Task.sleep(nanoseconds: 120_000_000)
                guard !Task.isCancelled else { return }
                await MainActor.run {
                    performSuggestionUpdate()
                }
            }
            return
        }

        // If delay is 0, show immediately
        if autocompleteDelay <= 0 {
            performSuggestionUpdate()
        } else {
            // Debounce with delay
            suggestionTask = Task {
                try? await Task.sleep(nanoseconds: UInt64(autocompleteDelay * 1_000_000_000))
                guard !Task.isCancelled else { return }
                await MainActor.run {
                    performSuggestionUpdate()
                }
            }
        }
    }

    func performSuggestionUpdate() {
        let selectedRange = self.selectedRange()
        let text = self.string as NSString

        // Only suggest when cursor is at the end of a word (no selection)
        guard selectedRange.length == 0 else {
            hideSuggestion()
            return
        }

        let cursorPosition = selectedRange.location
        guard cursorPosition > 0 else {
            hideSuggestion()
            return
        }

        // Check suggestion mode
        if suggestionMode == "sentence" {
            // Sentence mode: always show beta message
            let suggestion = WordSuggestionManager.shared.getSentenceSuggestion()
            suggestionWordStart = cursorPosition
            showGhostText(suggestion, at: cursorPosition)
            return
        }

        // Word mode: find word and suggest completion
        // Find word start
        var wordStart = cursorPosition
        while wordStart > 0 {
            let charIndex = wordStart - 1
            let char = text.substring(with: NSRange(location: charIndex, length: 1))
            if char.rangeOfCharacter(from: CharacterSet.alphanumerics) == nil {
                break
            }
            wordStart -= 1
        }

        // Get the current word prefix
        let wordLength = cursorPosition - wordStart
        guard wordLength >= 2 else { // Only suggest after 2+ characters
            hideSuggestion()
            return
        }

        let currentWord = text.substring(with: NSRange(location: wordStart, length: wordLength))

        // Get suggestion
        if let suggestion = WordSuggestionManager.shared.getSuggestion(for: currentWord) {
            suggestionWordStart = wordStart
            showGhostText(suggestion, at: cursorPosition)
        } else {
            hideSuggestion()
        }
    }

    func showGhostText(_ text: String, at position: Int) {
        guard !text.isEmpty, let ts = textStorage else {
            currentSuggestion = nil
            return
        }
        // Drop previous ghost first (callers compute position on clean
        // storage; this is just a double-guard).
        if ghostRange != nil {
            clearInlineGhost()
        }
        let pos = min(position, ts.length)

        // Don't preview text already present on the right (mid-word cursor
        // whose suffix matches, e.g. "hell|o" suggesting "o").
        let ns = string as NSString
        if pos < ns.length {
            let checkLen = min((text as NSString).length, ns.length - pos)
            if checkLen > 0,
               ns.substring(with: NSRange(location: pos, length: checkLen)) == (text as NSString).substring(to: checkLen) {
                currentSuggestion = nil
                return
            }
        }

        isApplyingGhost = true
        undoManager?.disableUndoRegistration()
        ts.replaceCharacters(in: NSRange(location: pos, length: 0), with: text)
        let inserted = NSRange(location: pos, length: (text as NSString).length)
        let font = self.font ?? NSFont.systemFont(ofSize: 14)
        ts.addAttributes([
            .font: font,
            .foregroundColor: NSColor.gray.withAlphaComponent(autocompleteOpacity)
        ], range: inserted)
        undoManager?.enableUndoRegistration()
        ghostRange = inserted
        currentSuggestion = text
        // Park caret before the ghost; right-side text is pushed by layout.
        setSelectedRange(NSRange(location: pos, length: 0))
        isApplyingGhost = false
    }

    func hideSuggestion() {
        suggestionTask?.cancel()
        clearInlineGhost()
    }

    func acceptSuggestion() -> Bool {
        guard let suggestion = currentSuggestion, !suggestion.isEmpty,
              let range = ghostRange,
              let ts = textStorage,
              range.location + range.length <= ts.length,
              ts.attributedSubstring(from: range).string == suggestion else {
            return false
        }
        suggestionTask?.cancel()

        // Ghost chars bypassed undo; re-insert as one real edit so Tab-accept
        // is a single undo unit.
        let loc = range.location
        isApplyingGhost = true
        undoManager?.disableUndoRegistration()
        ts.deleteCharacters(in: range)
        undoManager?.enableUndoRegistration()
        ghostRange = nil
        currentSuggestion = nil
        setSelectedRange(NSRange(location: loc, length: 0))
        isApplyingGhost = false

        replaceCharacters(in: NSRange(location: loc, length: 0), with: suggestion)

        // Move cursor to end of inserted text
        let newPosition = loc + (suggestion as NSString).length
        setSelectedRange(NSRange(location: newPosition, length: 0))
        return true
    }
}
#endif
