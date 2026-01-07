//
//  Slash.swift
//  MonkeyNote
//
//  Extension for slash command menu functionality
//

#if os(macOS)
import AppKit

// MARK: - Slash Command Menu
extension CursorTextView {
    
    func showSlashMenu() {
        guard let layoutManager = layoutManager,
              let textContainer = textContainer,
              let window = self.window else { return }
        
        let selectedRange = self.selectedRange()
        slashCommandRange = NSRange(location: selectedRange.location - 1, length: 1) // The "/" character
        
        // Get cursor position in window coordinates
        let glyphRange = layoutManager.glyphRange(forCharacterRange: selectedRange, actualCharacterRange: nil)
        var cursorRect = layoutManager.boundingRect(forGlyphRange: glyphRange, in: textContainer)
        cursorRect.origin.x += textContainerInset.width
        cursorRect.origin.y += textContainerInset.height
        
        // Convert to window coordinates
        let rectInView = convert(cursorRect, to: nil)
        let rectInWindow = window.convertToScreen(NSRect(origin: rectInView.origin, size: CGSize(width: 1, height: cursorRect.height)))
        
        slashCommandController.show(
            at: NSPoint(x: rectInWindow.origin.x, y: rectInWindow.origin.y),
            in: window,
            onSelect: { [weak self] command in
                self?.handleSlashCommand(command)
            },
            onDismiss: { [weak self] in
                self?.slashCommandRange = nil
            }
        )
    }
    
    func dismissSlashMenu() {
        slashCommandController.dismiss()
        slashCommandRange = nil
        slashFilterText = ""
    }
    
    func handleSlashCommand(_ command: SlashCommand) {
        guard let range = slashCommandRange else { return }
        
        // Replace "/" and any filter text with the command prefix
        replaceCharacters(in: range, with: command.prefix)
        
        // Set cursor position right after the inserted prefix
        let newCursorPosition = range.location + command.prefix.utf16.count
        setSelectedRange(NSRange(location: newCursorPosition, length: 0))
        
        slashCommandRange = nil
        slashFilterText = ""
    }
    
    /// Handle key down events when slash command menu is visible
    /// Returns true if the event was handled
    func handleSlashCommandKeyDown(with event: NSEvent) -> Bool {
        switch event.keyCode {
        case 126: // Up arrow
            slashCommandController.moveUp()
            return true
        case 125: // Down arrow
            slashCommandController.moveDown()
            return true
        case 36: // Enter
            if slashCommandController.hasResults {
                slashCommandController.selectCurrent()
            } else {
                // No results, just dismiss and let enter pass through
                dismissSlashMenu()
                return false
            }
            return true
        case 53: // Escape
            dismissSlashMenu()
            return true
        case 51: // Delete/Backspace
            // Handle backspace - update filter or dismiss
            if slashFilterText.isEmpty {
                // If filter is empty, backspace deletes the "/" and dismisses menu
                dismissSlashMenu()
                super.deleteBackward(nil)
            } else {
                // Remove last character from filter
                slashFilterText.removeLast()
                slashCommandController.updateFilter(slashFilterText)
                super.deleteBackward(nil)
            }
            return true
        default:
            // Let other keys (letters, etc.) pass through to insertText
            return false
        }
    }
    
    /// Handle insert text when slash command menu is visible
    /// Returns true if the event was handled
    func handleSlashCommandInsertText(_ str: String, replacementRange: NSRange) -> Bool {
        // Only allow alphanumeric characters for filtering
        if str.rangeOfCharacter(from: CharacterSet.alphanumerics) != nil {
            slashFilterText += str
            slashCommandController.updateFilter(slashFilterText)
            super.insertText(str, replacementRange: replacementRange)
            
            // Update the slash command range to include filter text
            if let range = slashCommandRange {
                slashCommandRange = NSRange(location: range.location, length: 1 + slashFilterText.utf16.count)
            }
            return true
        } else if str == " " || str == "\n" || str == "\t" {
            // Space, newline, or tab dismisses the menu
            dismissSlashMenu()
            super.insertText(str, replacementRange: replacementRange)
            return true
        } else {
            // Other special characters dismiss the menu
            dismissSlashMenu()
            return false
        }
    }
    
    /// Check if "/" was typed at the beginning of a line and show menu
    func handleSlashAtLineStart(_ str: String) {
        guard str == "/" else { return }
        
        let selectedRange = self.selectedRange()
        let text = self.string as NSString
        
        // Check if "/" is at the start of a line (after newline or at position 0)
        let slashPosition = selectedRange.location - 1
        if slashPosition < 0 { return }
        
        let isAtLineStart: Bool
        if slashPosition == 0 {
            isAtLineStart = true
        } else {
            let prevChar = text.substring(with: NSRange(location: slashPosition - 1, length: 1))
            isAtLineStart = prevChar == "\n"
        }
        
        if isAtLineStart {
            slashFilterText = ""  // Reset filter text when opening menu
            showSlashMenu()
        }
    }
}
#endif
