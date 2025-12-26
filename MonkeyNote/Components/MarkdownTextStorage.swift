//
//  MarkdownTextStorage.swift
//  MonkeyNote
//
//  Created on 26/12/25.
//

#if os(macOS)
import AppKit

// MARK: - Markdown Text Storage
class MarkdownTextStorage: NSTextStorage {
    
    // MARK: - Properties
    private let backingStore = NSMutableAttributedString()
    private let parser = MarkdownParser.shared
    
    var baseFont: NSFont = NSFont.systemFont(ofSize: 14) {
        didSet {
            reprocessMarkdown()
        }
    }
    
    var baseTextColor: NSColor = .labelColor {
        didSet {
            reprocessMarkdown()
        }
    }
    
    // Enable/disable markdown rendering (default: true)
    var markdownRenderEnabled: Bool = true {
        didSet {
            if oldValue != markdownRenderEnabled {
                reprocessMarkdown()
            }
        }
    }
    
    // Current cursor position - updated by text view
    var cursorPosition: Int = 0 {
        didSet {
            if oldValue != cursorPosition {
                updateSyntaxVisibility()
            }
        }
    }
    
    // Track if we're currently processing to avoid recursion
    private var isProcessing = false
    
    // Cache parsed matches for performance
    private var cachedMatches: [MarkdownMatch] = []
    private var lastParsedString: String = ""
    
    // MARK: - NSTextStorage Required Overrides
    
    override var string: String {
        return backingStore.string
    }
    
    override func attributes(at location: Int, effectiveRange range: NSRangePointer?) -> [NSAttributedString.Key : Any] {
        guard location < backingStore.length else {
            return [:]
        }
        return backingStore.attributes(at: location, effectiveRange: range)
    }
    
    override func replaceCharacters(in range: NSRange, with str: String) {
        beginEditing()
        
        backingStore.replaceCharacters(in: range, with: str)
        edited(.editedCharacters, range: range, changeInLength: str.utf16.count - range.length)
        
        endEditing()
    }
    
    override func setAttributes(_ attrs: [NSAttributedString.Key : Any]?, range: NSRange) {
        guard range.location + range.length <= backingStore.length else { return }
        
        beginEditing()
        backingStore.setAttributes(attrs, range: range)
        edited(.editedAttributes, range: range, changeInLength: 0)
        endEditing()
    }
    
    // MARK: - Processing
    
    override func processEditing() {
        // Invalidate cache when text changes
        lastParsedString = ""
        
        // Apply markdown styling to the entire document
        if !isProcessing {
            isProcessing = true
            applyFullMarkdownStyling()
            isProcessing = false
        }
        
        super.processEditing()
    }
    
    // MARK: - Full Markdown Styling
    
    private func applyFullMarkdownStyling() {
        guard backingStore.length > 0 else { return }
        
        let fullRange = NSRange(location: 0, length: backingStore.length)
        
        // Reset all attributes to base
        backingStore.setAttributes([
            .font: baseFont,
            .foregroundColor: baseTextColor
        ], range: fullRange)
        
        // If markdown rendering is disabled, just use plain text styling
        guard markdownRenderEnabled else {
            cachedMatches = []
            lastParsedString = string
            return
        }
        
        // Parse and cache matches
        let text = string
        cachedMatches = parser.parse(text)
        lastParsedString = text
        
        // Apply styling to all matches
        for match in cachedMatches {
            applyMatchStyling(match, cursorInRange: isCursorInMatch(match))
        }
    }
    
    // MARK: - Apply Styling to Single Match
    
    private func applyMatchStyling(_ match: MarkdownMatch, cursorInRange: Bool) {
        // Validate ranges
        guard match.range.location + match.range.length <= backingStore.length,
              match.contentRange.location + match.contentRange.length <= backingStore.length else {
            return
        }
        
        // Apply style to content
        let styleAttributes = parser.attributes(for: match.style, baseFont: baseFont)
        
        // Merge with base attributes
        var contentAttributes: [NSAttributedString.Key: Any] = [
            .foregroundColor: baseTextColor
        ]
        contentAttributes.merge(styleAttributes) { _, new in new }
        
        backingStore.addAttributes(contentAttributes, range: match.contentRange)
        
        // Handle syntax visibility based on cursor position
        for syntaxRange in match.syntaxRanges {
            guard syntaxRange.location + syntaxRange.length <= backingStore.length else { continue }
            
            if cursorInRange {
                // Show syntax when cursor is in range - use muted color
                backingStore.addAttributes(parser.visibleSyntaxAttributes(baseFont: baseFont), range: syntaxRange)
            } else {
                // Hide syntax when cursor is not in range
                backingStore.addAttributes(parser.hiddenSyntaxAttributes, range: syntaxRange)
            }
        }
        
        // Store URL for links
        if let url = match.url {
            if case .link = match.style {
                backingStore.addAttribute(.link, value: url, range: match.contentRange)
            } else if case .image = match.style {
                backingStore.addAttribute(.link, value: url, range: match.contentRange)
            }
        }
    }
    
    // MARK: - Cursor Position Helpers
    
    private func isCursorInMatch(_ match: MarkdownMatch) -> Bool {
        // Check if cursor is within the full range of the match (including syntax)
        return cursorPosition >= match.range.location && 
               cursorPosition <= match.range.location + match.range.length
    }
    
    // MARK: - Update Syntax Visibility
    
    func updateSyntaxVisibility() {
        // Skip syntax visibility updates if markdown rendering is disabled
        guard markdownRenderEnabled, !isProcessing, backingStore.length > 0 else { return }
        
        isProcessing = true
        
        beginEditing()
        
        // Reparse if needed
        if lastParsedString != string {
            cachedMatches = parser.parse(string)
            lastParsedString = string
        }
        
        // Update visibility for all matches
        for match in cachedMatches {
            guard match.range.location + match.range.length <= backingStore.length else { continue }
            
            let cursorInRange = isCursorInMatch(match)
            
            for syntaxRange in match.syntaxRanges {
                guard syntaxRange.location + syntaxRange.length <= backingStore.length else { continue }
                
                if cursorInRange {
                    // Show syntax
                    backingStore.addAttributes(parser.visibleSyntaxAttributes(baseFont: baseFont), range: syntaxRange)
                } else {
                    // Hide syntax
                    backingStore.addAttributes(parser.hiddenSyntaxAttributes, range: syntaxRange)
                }
            }
        }
        
        let fullRange = NSRange(location: 0, length: backingStore.length)
        edited(.editedAttributes, range: fullRange, changeInLength: 0)
        
        endEditing()
        
        isProcessing = false
    }
    
    // MARK: - Full Reprocess
    
    func reprocessMarkdown() {
        guard backingStore.length > 0 else { return }
        
        isProcessing = true
        
        beginEditing()
        
        applyFullMarkdownStyling()
        
        let fullRange = NSRange(location: 0, length: backingStore.length)
        edited(.editedAttributes, range: fullRange, changeInLength: 0)
        
        endEditing()
        
        isProcessing = false
    }
}

// MARK: - Convenience Extension
extension MarkdownTextStorage {
    
    /// Get the visible text (with syntax hidden but still in storage)
    var visibleText: String {
        return string
    }
    
    /// Get plain text without any markdown syntax
    var plainText: String {
        var result = string
        let matches = parser.parse(string).reversed()
        
        for match in matches {
            for syntaxRange in match.syntaxRanges.sorted(by: { $0.location > $1.location }) {
                guard syntaxRange.location + syntaxRange.length <= result.utf16.count else { continue }
                let start = result.index(result.startIndex, offsetBy: syntaxRange.location)
                let end = result.index(start, offsetBy: syntaxRange.length)
                result.removeSubrange(start..<end)
            }
        }
        
        return result
    }
}
#endif
