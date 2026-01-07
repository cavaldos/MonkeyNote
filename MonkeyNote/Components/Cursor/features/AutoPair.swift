//
//  AutoPair.swift
//  MonkeyNote
//
//  Extension for auto-pairing brackets and quotes
//

#if os(macOS)
import AppKit

// MARK: - Auto Pair Brackets/Quotes
extension CursorTextView {
    
    /// Handle auto pair for brackets and quotes
    /// Returns true if the event was handled
    func handleAutoPair(_ str: String, replacementRange: NSRange) -> Bool {
        guard autoPairEnabled else { return false }
        
        let selectedRange = self.selectedRange()
        let text = self.string as NSString
        
        // Check if typing a closing character that already exists at cursor
        if closingChars.contains(str) && selectedRange.location < text.length {
            let nextChar = text.substring(with: NSRange(location: selectedRange.location, length: 1))
            if nextChar == str {
                // Skip over the existing closing character instead of inserting
                self.setSelectedRange(NSRange(location: selectedRange.location + 1, length: 0))
                
                // Update cursor position in MarkdownTextStorage
                if let textStorage = self.textStorage as? MarkdownTextStorage {
                    textStorage.cursorPosition = self.selectedRange().location
                }
                return true
            }
        }
        
        // Check if we should auto pair this character
        if let closingChar = autoPairMap[str] {
            // For quotes, check if we're in the middle of a word (don't auto pair)
            if str == "\"" || str == "'" || str == "`" {
                if selectedRange.location > 0 {
                    let prevChar = text.substring(with: NSRange(location: selectedRange.location - 1, length: 1))
                    // Don't auto pair if previous char is alphanumeric (e.g., typing it's)
                    if prevChar.rangeOfCharacter(from: CharacterSet.alphanumerics) != nil {
                        return false
                    }
                }
            }
            
            // If there's selected text, wrap it with the pair
            if selectedRange.length > 0 {
                let selectedText = text.substring(with: selectedRange)
                let wrappedText = str + selectedText + closingChar
                self.replaceCharacters(in: selectedRange, with: wrappedText)
                // Position cursor after the wrapped text
                self.setSelectedRange(NSRange(location: selectedRange.location + wrappedText.utf16.count, length: 0))
                
                // Update cursor position in MarkdownTextStorage
                if let textStorage = self.textStorage as? MarkdownTextStorage {
                    textStorage.cursorPosition = self.selectedRange().location
                }
                return true
            }
            
            // Insert both opening and closing, position cursor in between
            let pairText = str + closingChar
            super.insertText(pairText, replacementRange: replacementRange)
            
            // Move cursor back by 1 to be between the pair
            let newPosition = self.selectedRange().location - 1
            self.setSelectedRange(NSRange(location: newPosition, length: 0))
            
            // Update cursor position in MarkdownTextStorage
            if let textStorage = self.textStorage as? MarkdownTextStorage {
                textStorage.cursorPosition = self.selectedRange().location
            }
            
            // Hide suggestion since we typed a special character
            hideSuggestion()
            return true
        }
        
        return false
    }
}
#endif
