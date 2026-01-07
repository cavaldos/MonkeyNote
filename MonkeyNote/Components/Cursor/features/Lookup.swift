//
//  Lookup.swift
//  MonkeyNote
//
//  Extension for dictionary lookup functionality (triggered by "word\")
//

#if os(macOS)
import AppKit

// MARK: - Dictionary Lookup
extension CursorTextView {
    
    /// Called when "\" is typed - find the word before it and show lookup menu
    func showDictionaryLookupForWordBeforeBackslash() {
        guard let window = self.window else { return }
        
        let selectedRange = self.selectedRange()
        let text = self.string as NSString
        
        // Backslash was just inserted at cursor position - 1
        let backslashPosition = selectedRange.location - 1
        guard backslashPosition >= 0 else { return }
        
        // Find the word before the backslash
        var wordStart = backslashPosition
        while wordStart > 0 {
            let charIndex = wordStart - 1
            let char = text.substring(with: NSRange(location: charIndex, length: 1))
            if char.rangeOfCharacter(from: CharacterSet.alphanumerics) == nil {
                break
            }
            wordStart -= 1
        }
        
        // Must have at least 1 character before backslash
        guard wordStart < backslashPosition else {
            // No word before backslash, just let it be typed normally
            return
        }
        
        let wordToLookup = text.substring(with: NSRange(location: wordStart, length: backslashPosition - wordStart))
        
        // Store the range of "word\" (including backslash)
        dictionaryLookupRange = NSRange(location: wordStart, length: backslashPosition - wordStart + 1)
        
        // Get cursor position in screen coordinates for menu positioning
        guard let layoutManager = layoutManager,
              let textContainer = textContainer else { return }
        
        let glyphRange = layoutManager.glyphRange(forCharacterRange: NSRange(location: backslashPosition, length: 1), actualCharacterRange: nil)
        var cursorRect = layoutManager.boundingRect(forGlyphRange: glyphRange, in: textContainer)
        cursorRect.origin.x += textContainerInset.width
        cursorRect.origin.y += textContainerInset.height
        
        let rectInView = convert(cursorRect, to: nil)
        let rectInWindow = window.convertToScreen(NSRect(origin: rectInView.origin, size: CGSize(width: 1, height: cursorRect.height)))
        
        // Create controller if needed
        if dictionaryLookupController == nil {
            dictionaryLookupController = DictionaryLookupWindowController()
        }
        
        // Show the menu
        dictionaryLookupController?.show(
            at: NSPoint(x: rectInWindow.origin.x, y: rectInWindow.origin.y),
            in: window,
            word: wordToLookup,
            onDismiss: { [weak self] in
                self?.dictionaryLookupRange = nil
            }
        )
    }
    
    func dismissDictionaryLookup() {
        dictionaryLookupController?.dismiss()
        dictionaryLookupRange = nil
    }
    
    /// Handle key down events when dictionary lookup is visible
    /// Returns true if the event was handled
    func handleDictionaryLookupKeyDown(with event: NSEvent) -> Bool {
        // Escape dismisses the lookup
        if event.keyCode == 53 {
            dismissDictionaryLookup()
            return true
        }
        // Any other key dismisses and continues normal behavior
        dismissDictionaryLookup()
        return false
    }
}
#endif
