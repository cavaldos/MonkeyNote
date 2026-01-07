//
//  AutoContinue.swift
//  MonkeyNote
//
//  Extension for auto-continuing lists (bullet and numbered)
//

#if os(macOS)
import AppKit

// MARK: - List Auto Continue
extension CursorTextView {
    
    /// Handle Tab key for list formatting and autocomplete
    /// Returns true if the event was handled
    func handleTabKey(with event: NSEvent) -> Bool {
        // Try to accept autocomplete suggestion first
        if acceptSuggestion() {
            return true
        }
        
        let selectedRange = self.selectedRange()
        let text = self.string as NSString
        
        // Check if character BEFORE cursor is "-" or "."
        if selectedRange.location > 0 {
            let prevCharIndex = selectedRange.location - 1
            if prevCharIndex < text.length {
                let prevChar = text.substring(with: NSRange(location: prevCharIndex, length: 1))
                
                // Check for "-" or "." at start of line for bullet list
                if prevChar == "-" || prevChar == "." {
                    // Verify it's at the start of the line
                    let lineRange = text.lineRange(for: NSRange(location: prevCharIndex, length: 0))
                    let isAtLineStart = prevCharIndex == lineRange.location
                    
                    if isAtLineStart {
                        // Calculate content length on this line only (exclude newline character)
                        var lineContentLength = lineRange.length
                        if lineRange.location + lineRange.length <= text.length {
                            let lineContent = text.substring(with: lineRange)
                            if lineContent.hasSuffix("\n") {
                                lineContentLength -= 1
                            }
                        }
                        
                        // Get remaining text on this line only (after "-" or ".")
                        let afterCharStart = prevCharIndex + 1
                        let afterCharLength = lineRange.location + lineContentLength - afterCharStart
                        guard afterCharLength >= 0 else {
                            // No content after "-" or "." on this line, just convert to bullet
                            let rangeToReplace = NSRange(location: prevCharIndex, length: 1)
                            self.replaceCharacters(in: rangeToReplace, with: "• ")
                            self.setSelectedRange(NSRange(location: prevCharIndex + "• ".utf16.count, length: 0))
                            return true
                        }
                        
                        let rangeAfterChar = NSRange(location: afterCharStart, length: afterCharLength)
                        let remainingText = text.substring(with: rangeAfterChar)
                        
                        // Replace the entire line from dash/dot to end of line content with bullet + remaining text
                        let lineAfterChar = NSRange(location: prevCharIndex, length: 1 + afterCharLength)
                        let newText = "• " + remainingText.trimmingCharacters(in: .whitespacesAndNewlines)
                        self.replaceCharacters(in: lineAfterChar, with: newText)
                        self.setSelectedRange(NSRange(location: prevCharIndex + newText.utf16.count, length: 0))
                        return true
                    }
                }
                
                // Check for numbered list pattern like "1."
                if prevCharIndex >= 1 {
                    let twoCharsBefore = text.substring(with: NSRange(location: prevCharIndex - 1, length: 2))
                    if let regex = try? NSRegularExpression(pattern: "^\\d\\.", options: []),
                       regex.firstMatch(in: twoCharsBefore, options: [], range: NSRange(location: 0, length: 2)) != nil {
                        let lineRange = text.lineRange(for: NSRange(location: prevCharIndex - 1, length: 0))
                        
                        // Calculate content length on this line only (exclude newline character)
                        var lineContentLength = lineRange.length
                        if lineRange.location + lineRange.length <= text.length {
                            let lineContent = text.substring(with: lineRange)
                            if lineContent.hasSuffix("\n") {
                                lineContentLength -= 1
                            }
                        }
                        
                        // Get remaining text on this line only (after "1.")
                        let afterNumberStart = prevCharIndex + 1
                        let afterNumberLength = lineRange.location + lineContentLength - afterNumberStart
                        guard afterNumberLength >= 0 else {
                            // No content after "1." on this line, just add space
                            let lineAfterNumber = NSRange(location: prevCharIndex - 1, length: 2)
                            let newText = twoCharsBefore + " "
                            self.replaceCharacters(in: lineAfterNumber, with: newText)
                            self.setSelectedRange(NSRange(location: prevCharIndex - 1 + newText.utf16.count, length: 0))
                            return true
                        }
                        
                        let rangeAfterNumber = NSRange(location: afterNumberStart, length: afterNumberLength)
                        let remainingText = text.substring(with: rangeAfterNumber)
                        
                        // Replace the number pattern and remaining text on this line only
                        let lineAfterNumber = NSRange(location: prevCharIndex - 1, length: 2 + afterNumberLength)
                        let newText = twoCharsBefore + " " + remainingText.trimmingCharacters(in: .whitespacesAndNewlines)
                        self.replaceCharacters(in: lineAfterNumber, with: newText)
                        self.setSelectedRange(NSRange(location: prevCharIndex - 1 + newText.utf16.count, length: 0))
                        return true
                    }
                }
            }
        }
        
        super.insertText("\t")
        return true
    }
    
    /// Handle Shift + Enter - soft line break (continue same list item)
    /// Returns true if the event was handled
    func handleShiftEnter() -> Bool {
        let selectedRange = self.selectedRange()
        let text = self.string as NSString
        
        let lineRange = text.lineRange(for: selectedRange)
        let currentLine = text.substring(with: lineRange)
        let trimmedLine = currentLine.trimmingCharacters(in: .whitespaces)
        
        // Check if we're in a numbered list
        if let regex = try? NSRegularExpression(pattern: "^(\\d+)\\.", options: []),
           regex.firstMatch(in: trimmedLine, options: [], range: NSRange(location: 0, length: trimmedLine.utf16.count)) != nil {
            // Insert newline with indent (3 spaces to align with text after "1. ")
            super.insertText("\n   ")
            return true
        }
        
        // Check if we're in a bullet list
        if trimmedLine.hasPrefix("•") {
            // Insert newline with indent (2 spaces to align with text after "• ")
            super.insertText("\n  ")
            return true
        }
        
        // Default: just insert newline
        super.insertText("\n")
        return true
    }
    
    /// Handle Enter key for list continuation
    /// Returns true if the event was handled
    func handleEnterKey() -> Bool {
        let selectedRange = self.selectedRange()
        let text = self.string as NSString
        
        let lineRange = text.lineRange(for: selectedRange)
        let currentLine = text.substring(with: lineRange)
        let trimmedLine = currentLine.trimmingCharacters(in: .whitespaces)
        
        // Handle bullet list
        if trimmedLine.hasPrefix("•") {
            // Get content after bullet (handle both "• " and "•")
            var bulletContent: String
            if trimmedLine.hasPrefix("• ") {
                bulletContent = String(trimmedLine.dropFirst("• ".count)).trimmingCharacters(in: .whitespaces)
            } else {
                bulletContent = String(trimmedLine.dropFirst("•".count)).trimmingCharacters(in: .whitespaces)
            }
            
            if bulletContent.isEmpty {
                // Remove the bullet line entirely
                let linesBefore = text.substring(with: NSRange(location: 0, length: lineRange.location))
                let linesAfter = text.substring(with: NSRange(location: lineRange.location + lineRange.length, length: text.length - (lineRange.location + lineRange.length)))
                let newString = linesBefore + linesAfter
                self.string = newString
                self.setSelectedRange(NSRange(location: lineRange.location, length: 0))
            } else {
                super.insertText("\n• ")
                self.setSelectedRange(NSRange(location: selectedRange.location + "\n• ".utf16.count, length: 0))
            }
            return true
        }
        
        // Handle numbered list
        if let regex = try? NSRegularExpression(pattern: "^(\\d+)\\.", options: []),
           let match = regex.firstMatch(in: trimmedLine, options: [], range: NSRange(location: 0, length: trimmedLine.utf16.count)) {
            let numberRange = match.range(at: 1)
            let numberString = (trimmedLine as NSString).substring(with: numberRange)
            let number = Int(numberString) ?? 1
            let contentStart = match.range.location + match.range.length
            let contentLength = trimmedLine.utf16.count - contentStart
            let content = (trimmedLine as NSString).substring(with: NSRange(location: contentStart, length: contentLength)).trimmingCharacters(in: .whitespaces)
            
            if content.isEmpty {
                let linesBefore = text.substring(with: NSRange(location: 0, length: lineRange.location))
                let linesAfter = text.substring(with: NSRange(location: lineRange.location + lineRange.length, length: text.length - (lineRange.location + lineRange.length)))
                let newString = linesBefore + linesAfter
                self.string = newString
                self.setSelectedRange(NSRange(location: lineRange.location, length: 0))
            } else {
                let nextNumber = number + 1
                let nextLineText = "\n\(nextNumber). "
                super.insertText(nextLineText)
                self.setSelectedRange(NSRange(location: selectedRange.location + nextLineText.utf16.count, length: 0))
            }
            return true
        }
        
        return false
    }
    
    /// Handle space after "." or "-" at line start to convert to bullet
    /// Returns true if the event was handled
    func handleBulletConversion(_ str: String) -> Bool {
        guard str == " " else { return false }
        
        let selectedRange = self.selectedRange()
        let text = self.string as NSString
        
        if selectedRange.location > 0 {
            let prevCharIndex = selectedRange.location - 1
            let prevChar = text.substring(with: NSRange(location: prevCharIndex, length: 1))
            
            // Check for "." or "-" at start of line
            if prevChar == "." || prevChar == "-" {
                let lineRange = text.lineRange(for: NSRange(location: prevCharIndex, length: 0))
                let isAtLineStart = prevCharIndex == lineRange.location
                
                if isAtLineStart {
                    // Replace "." or "-" with bullet
                    let rangeToReplace = NSRange(location: prevCharIndex, length: 1)
                    self.replaceCharacters(in: rangeToReplace, with: "• ")
                    self.setSelectedRange(NSRange(location: prevCharIndex + "• ".utf16.count, length: 0))
                    
                    // Update cursor position in MarkdownTextStorage
                    if let textStorage = self.textStorage as? MarkdownTextStorage {
                        textStorage.cursorPosition = self.selectedRange().location
                    }
                    return true
                }
            }
        }
        
        return false
    }
    
    /// Handle double-tap navigation (Delete, Left Arrow, Right Arrow)
    /// Returns true if the event was handled
    func handleDoubleTapNavigation(with event: NSEvent) -> Bool {
        guard doubleTapNavigationEnabled else { return false }
        
        let currentKeyCode = event.keyCode
        let now = Date()
        let timeSinceLastKey = now.timeIntervalSince(lastKeyTime) * 1000 // Convert to milliseconds
        
        // Check if this is a double-tap (same key pressed within delay threshold)
        let isDoubleTap = currentKeyCode == lastKeyCode && timeSinceLastKey <= doubleTapDelay
        
        // Update tracking for next check
        lastKeyCode = currentKeyCode
        lastKeyTime = now
        
        if isDoubleTap {
            switch currentKeyCode {
            case 51: // Delete/Backspace - delete word backward (like Option+Delete)
                // First delete undoes the character deleted by first tap, then delete word
                deleteWordBackward(nil)
                return true
            case 123: // Left Arrow - move to previous word (like Option+Left)
                // First move undoes the character move by first tap
                moveRight(nil)
                moveWordLeft(nil)
                return true
            case 124: // Right Arrow - move to next word (like Option+Right)
                // First move undoes the character move by first tap
                moveLeft(nil)
                moveWordRight(nil)
                return true
            default:
                break
            }
        }
        
        return false
    }
}
#endif
