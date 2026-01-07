//
//  MarkdownWYSIWYG.swift
//  MonkeyNote
//
//  Extension for markdown formatting (bold, italic, code, etc.)
//

#if os(macOS)
import AppKit

// MARK: - Markdown WYSIWYG Formatting
extension CursorTextView {
    
    /// Handle formatting shortcuts (Cmd+B, Cmd+I, Cmd+E)
    /// Returns true if the event was handled
    func handleFormattingShortcut(with event: NSEvent) -> Bool {
        let selectedRange = self.selectedRange()
        guard selectedRange.length > 0 else { return false }
        
        switch event.charactersIgnoringModifiers?.lowercased() {
        case "b":
            applyFormatting(action: .bold, range: selectedRange)
            return true
        case "i":
            applyFormatting(action: .italic, range: selectedRange)
            return true
        case "e":
            applyFormatting(action: .code, range: selectedRange)
            return true
        default:
            return false
        }
    }
    
    func applyFormatting(action: ToolbarAction, range: NSRange) {
        let text = self.string as NSString
        let selectedText = text.substring(with: range)
        
        // Get prefix and suffix for the action
        let (prefix, suffix) = getMarkdownSyntax(for: action)
        
        // Skip actions without prefix/suffix (handled separately)
        guard !prefix.isEmpty else {
            handleSpecialFormatting(action: action, range: range, text: text)
            return
        }
        
        // Check if formatting should be toggled off
        // Case 1: Selected text is wrapped with syntax (e.g., "**text**" selected)
        if selectedText.hasPrefix(prefix) && selectedText.hasSuffix(suffix) && selectedText.count >= prefix.count + suffix.count {
            let strippedText = String(selectedText.dropFirst(prefix.count).dropLast(suffix.count))
            performUndoableReplacement(in: range, with: strippedText)
            setSelectedRange(NSRange(location: range.location, length: strippedText.utf16.count))
            return
        }
        
        // Case 2: Text outside selection has the syntax (e.g., **"text"** where "text" is selected)
        let prefixLength = prefix.utf16.count
        let suffixLength = suffix.utf16.count
        
        if range.location >= prefixLength {
            let beforeRange = NSRange(location: range.location - prefixLength, length: prefixLength)
            let afterLocation = range.location + range.length
            
            if afterLocation + suffixLength <= text.length {
                let afterRange = NSRange(location: afterLocation, length: suffixLength)
                let beforeText = text.substring(with: beforeRange)
                let afterText = text.substring(with: afterRange)
                
                if beforeText == prefix && afterText == suffix {
                    // Remove the surrounding syntax
                    let fullRange = NSRange(location: beforeRange.location, length: prefixLength + range.length + suffixLength)
                    performUndoableReplacement(in: fullRange, with: selectedText)
                    setSelectedRange(NSRange(location: beforeRange.location, length: selectedText.utf16.count))
                    return
                }
            }
        }
        
        // Not formatted yet, add formatting
        let newText = "\(prefix)\(selectedText)\(suffix)"
        performUndoableReplacement(in: range, with: newText)
        
        // Select the text inside the formatting (without syntax)
        let newSelectionStart = range.location + prefix.utf16.count
        setSelectedRange(NSRange(location: newSelectionStart, length: selectedText.utf16.count))
    }
    
    /// Returns the prefix and suffix for a given formatting action
    func getMarkdownSyntax(for action: ToolbarAction) -> (prefix: String, suffix: String) {
        switch action {
        case .bold:
            return ("**", "**")
        case .italic:
            return ("_", "_")
        case .code:
            return ("`", "`")
        case .strikethrough:
            return ("~~", "~~")
        case .highlight:
            return ("==", "==")
        case .link:
            return ("[", "](url)")
        default:
            return ("", "")
        }
    }
    
    /// Handle special formatting actions (heading, list, alignLeft)
    func handleSpecialFormatting(action: ToolbarAction, range: NSRange, text: NSString) {
        switch action {
        case .heading:
            let lineRange = text.lineRange(for: range)
            let lineStart = lineRange.location
            let currentLine = text.substring(with: lineRange)
            
            if currentLine.hasPrefix("### ") {
                performUndoableReplacement(in: NSRange(location: lineStart, length: 4), with: "")
            } else if currentLine.hasPrefix("## ") {
                performUndoableReplacement(in: NSRange(location: lineStart, length: 3), with: "### ")
            } else if currentLine.hasPrefix("# ") {
                performUndoableReplacement(in: NSRange(location: lineStart, length: 2), with: "## ")
            } else {
                performUndoableReplacement(in: NSRange(location: lineStart, length: 0), with: "# ")
            }
            
        case .list:
            let lineRange = text.lineRange(for: range)
            let lineStart = lineRange.location
            let currentLine = text.substring(with: lineRange)
            
            if currentLine.hasPrefix("• ") || currentLine.hasPrefix("- ") {
                performUndoableReplacement(in: NSRange(location: lineStart, length: 2), with: "")
            } else {
                performUndoableReplacement(in: NSRange(location: lineStart, length: 0), with: "• ")
            }
            
        case .alignLeft:
            // Alignment is not typically supported in plain markdown
            break
            
        default:
            break
        }
    }
    
    /// Performs a text replacement with proper undo support that doesn't restore selection state
    func performUndoableReplacement(in range: NSRange, with newText: String) {
        let text = self.string as NSString
        let oldText = text.substring(with: range)
        
        // Register undo action
        undoManager?.registerUndo(withTarget: self) { [weak self] _ in
            guard let self = self else { return }
            let newRange = NSRange(location: range.location, length: newText.utf16.count)
            self.performUndoableReplacement(in: newRange, with: oldText)
            // Place cursor at end of restored text (no selection)
            self.setSelectedRange(NSRange(location: range.location + oldText.utf16.count, length: 0))
        }
        
        // Perform the replacement
        replaceCharacters(in: range, with: newText)
        
        // Notify text did change
        didChangeText()
    }
    
    /// Notify MarkdownTextStorage about visible range for viewport-based rendering
    func updateMarkdownViewport() {
        guard let layoutManager = layoutManager,
              let textContainer = textContainer,
              let textStorage = textStorage as? MarkdownTextStorage else { return }
        
        let visibleRect = self.visibleRect
        guard visibleRect.height > 0 else { return }
        
        // Get visible character range
        let glyphRange = layoutManager.glyphRange(forBoundingRect: visibleRect, in: textContainer)
        let visibleCharRange = layoutManager.characterRange(forGlyphRange: glyphRange, actualGlyphRange: nil)
        
        // Notify text storage about visible range
        textStorage.updateVisibleRange(visibleCharRange)
    }
}
#endif
