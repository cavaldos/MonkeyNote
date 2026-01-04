//
//  MarkdownTextStorage.swift
//  MonkeyNote
//
//  Created by Claude on 04/01/26.
//

import AppKit
import SwiftTreeSitter
import TreeSitterMarkdown

/// Custom NSTextStorage that applies WYSIWYG markdown styling
/// - Parses markdown using Tree-sitter
/// - Hides syntax markers when cursor is not on that line
/// - Shows syntax markers when cursor is on that line (for editing)
class MarkdownTextStorage: NSTextStorage {
    
    // MARK: - Properties
    
    /// The underlying storage
    private var storage = NSMutableAttributedString()
    
    /// Markdown parser using Tree-sitter
    private let parser = MarkdownParser()
    
    /// Current theme for styling
    var theme: MarkdownTheme {
        didSet {
            reapplyMarkdownStyling()
        }
    }
    
    /// Current cursor position (used to determine which line to show syntax on)
    var cursorPosition: Int = 0 {
        didSet {
            if oldValue != cursorPosition {
                updateSyntaxVisibility()
            }
        }
    }
    
    /// Cached markdown elements from last parse
    private var cachedElements: [MarkdownElement] = []
    
    /// Range of the line where cursor is currently located
    private var currentLineRange: NSRange = NSRange(location: 0, length: 0)
    
    /// Track which element index the cursor was previously inside (for optimization)
    private var previousElementIndex: Int? = nil
    
    /// Track if we're in the middle of editing
    private var isProcessingEdits = false
    
    // MARK: - Initialization
    
    init(theme: MarkdownTheme) {
        self.theme = theme
        super.init()
    }
    
    required init?(coder: NSCoder) {
        self.theme = MarkdownTheme.light(baseFont: NSFont.systemFont(ofSize: 14))
        super.init(coder: coder)
    }
    
    required init?(pasteboardPropertyList propertyList: Any, ofType type: NSPasteboard.PasteboardType) {
        self.theme = MarkdownTheme.light(baseFont: NSFont.systemFont(ofSize: 14))
        super.init(pasteboardPropertyList: propertyList, ofType: type)
    }
    
    // MARK: - NSTextStorage Required Overrides
    
    override var string: String {
        return storage.string
    }
    
    override func attributes(at location: Int, effectiveRange range: NSRangePointer?) -> [NSAttributedString.Key: Any] {
        guard location < storage.length else {
            return [:]
        }
        return storage.attributes(at: location, effectiveRange: range)
    }
    
    override func replaceCharacters(in range: NSRange, with str: String) {
        beginEditing()
        storage.replaceCharacters(in: range, with: str)
        edited(.editedCharacters, range: range, changeInLength: str.utf16.count - range.length)
        endEditing()
    }
    
    override func setAttributes(_ attrs: [NSAttributedString.Key: Any]?, range: NSRange) {
        beginEditing()
        storage.setAttributes(attrs, range: range)
        edited(.editedAttributes, range: range, changeInLength: 0)
        endEditing()
    }
    
    // MARK: - Processing Edits
    
    override func processEditing() {
        // Prevent recursive calls
        guard !isProcessingEdits else {
            super.processEditing()
            return
        }
        
        isProcessingEdits = true
        
        // Apply base font to edited range
        let paragraphRange = (string as NSString).paragraphRange(for: editedRange)
        applyBaseStyle(to: paragraphRange)
        
        // Re-parse and apply markdown styling
        parseAndApplyMarkdown()
        
        isProcessingEdits = false
        
        super.processEditing()
    }
    
    // MARK: - Markdown Parsing & Styling
    
    /// Parse the entire text and apply markdown styling
    private func parseAndApplyMarkdown() {
        let text = storage.string
        guard !text.isEmpty else {
            cachedElements = []
            previousElementIndex = nil
            return
        }
        
        // Parse with Tree-sitter
        cachedElements = parser.parse(text)
        
        // Reset element tracking since elements changed
        previousElementIndex = nil
        
        // Update current line range based on cursor position
        updateCurrentLineRange()
        
        // Apply styles to all elements
        applyMarkdownStyles()
    }
    
    /// Reapply styling without re-parsing (used when theme changes)
    private func reapplyMarkdownStyling() {
        guard !storage.string.isEmpty else { return }
        
        beginEditing()
        
        // Reset to base style
        let fullRange = NSRange(location: 0, length: storage.length)
        applyBaseStyle(to: fullRange)
        
        // Re-apply markdown styles
        applyMarkdownStyles()
        
        edited(.editedAttributes, range: fullRange, changeInLength: 0)
        endEditing()
    }
    
    /// Apply base text style to a range
    private func applyBaseStyle(to range: NSRange) {
        guard range.location + range.length <= storage.length else { return }
        
        storage.addAttributes([
            .font: theme.baseFont,
            .foregroundColor: theme.baseColor
        ], range: range)
    }
    
    /// Apply markdown styles to all cached elements
    private func applyMarkdownStyles() {
        for element in cachedElements {
            applyStyle(for: element)
        }
    }
    
    /// Apply style for a single markdown element
    private func applyStyle(for element: MarkdownElement) {
        // Check if cursor is INSIDE this element (not just on the same line)
        let isCursorInElement = cursorPosition >= element.range.location && 
                                cursorPosition <= element.range.location + element.range.length
        
        switch element.type {
        case .bold:
            applyBoldStyle(element: element, showSyntax: isCursorInElement)
        case .italic:
            applyItalicStyle(element: element, showSyntax: isCursorInElement)
        case .code:
            applyCodeStyle(element: element, showSyntax: isCursorInElement)
        case .strikethrough:
            applyStrikethroughStyle(element: element, showSyntax: isCursorInElement)
        default:
            break
        }
    }
    
    // MARK: - Style Application
    
    /// Apply bold style (yellow color, hide ** when not on cursor line)
    private func applyBoldStyle(element: MarkdownElement, showSyntax: Bool) {
        guard element.range.location + element.range.length <= storage.length else { return }
        
        if showSyntax {
            // Show syntax: apply yellow to entire range including **
            storage.addAttributes([
                .foregroundColor: theme.boldColor
            ], range: element.range)
            
            // Dim the syntax markers
            for syntaxRange in element.syntaxRanges {
                guard syntaxRange.location + syntaxRange.length <= storage.length else { continue }
                storage.addAttributes([
                    .foregroundColor: theme.syntaxMarkerColor
                ], range: syntaxRange)
            }
        } else {
            // Hide syntax: make ** invisible (zero width or same as background)
            // Apply yellow to content only
            guard element.contentRange.location + element.contentRange.length <= storage.length else { return }
            
            storage.addAttributes([
                .foregroundColor: theme.boldColor
            ], range: element.contentRange)
            
            // Hide syntax markers by making them invisible
            for syntaxRange in element.syntaxRanges {
                guard syntaxRange.location + syntaxRange.length <= storage.length else { continue }
                // Use very small font and transparent color to "hide" the syntax
                storage.addAttributes([
                    .foregroundColor: NSColor.clear,
                    .font: NSFont.systemFont(ofSize: 0.1)  // Nearly invisible
                ], range: syntaxRange)
            }
        }
    }
    
    /// Apply italic style
    private func applyItalicStyle(element: MarkdownElement, showSyntax: Bool) {
        guard element.contentRange.location + element.contentRange.length <= storage.length else { return }
        
        let italicFont: NSFont
        if let baseFont = theme.italicFont {
            italicFont = baseFont
        } else {
            italicFont = NSFontManager.shared.convert(theme.baseFont, toHaveTrait: .italicFontMask)
        }
        
        if showSyntax {
            // Show syntax
            storage.addAttributes([
                .font: italicFont
            ], range: element.range)
            
            // Dim syntax markers
            for syntaxRange in element.syntaxRanges {
                guard syntaxRange.location + syntaxRange.length <= storage.length else { continue }
                storage.addAttributes([
                    .foregroundColor: theme.syntaxMarkerColor
                ], range: syntaxRange)
            }
        } else {
            // Hide syntax
            storage.addAttributes([
                .font: italicFont
            ], range: element.contentRange)
            
            // Hide syntax markers
            for syntaxRange in element.syntaxRanges {
                guard syntaxRange.location + syntaxRange.length <= storage.length else { continue }
                storage.addAttributes([
                    .foregroundColor: NSColor.clear,
                    .font: NSFont.systemFont(ofSize: 0.1)
                ], range: syntaxRange)
            }
        }
    }
    
    /// Apply code style
    private func applyCodeStyle(element: MarkdownElement, showSyntax: Bool) {
        guard element.contentRange.location + element.contentRange.length <= storage.length else { return }
        
        let codeFont = theme.codeFont ?? NSFont.monospacedSystemFont(ofSize: theme.baseFont.pointSize, weight: .regular)
        
        if showSyntax {
            storage.addAttributes([
                .font: codeFont,
                .foregroundColor: theme.codeColor,
                .backgroundColor: theme.codeBackgroundColor
            ], range: element.range)
            
            for syntaxRange in element.syntaxRanges {
                guard syntaxRange.location + syntaxRange.length <= storage.length else { continue }
                storage.addAttributes([
                    .foregroundColor: theme.syntaxMarkerColor
                ], range: syntaxRange)
            }
        } else {
            storage.addAttributes([
                .font: codeFont,
                .foregroundColor: theme.codeColor,
                .backgroundColor: theme.codeBackgroundColor
            ], range: element.contentRange)
            
            for syntaxRange in element.syntaxRanges {
                guard syntaxRange.location + syntaxRange.length <= storage.length else { continue }
                storage.addAttributes([
                    .foregroundColor: NSColor.clear,
                    .font: NSFont.systemFont(ofSize: 0.1)
                ], range: syntaxRange)
            }
        }
    }
    
    /// Apply strikethrough style
    private func applyStrikethroughStyle(element: MarkdownElement, showSyntax: Bool) {
        guard element.contentRange.location + element.contentRange.length <= storage.length else { return }
        
        if showSyntax {
            storage.addAttributes([
                .strikethroughStyle: NSUnderlineStyle.single.rawValue,
                .strikethroughColor: theme.strikethroughColor ?? theme.baseColor
            ], range: element.range)
            
            for syntaxRange in element.syntaxRanges {
                guard syntaxRange.location + syntaxRange.length <= storage.length else { continue }
                storage.addAttributes([
                    .foregroundColor: theme.syntaxMarkerColor
                ], range: syntaxRange)
            }
        } else {
            storage.addAttributes([
                .strikethroughStyle: NSUnderlineStyle.single.rawValue,
                .strikethroughColor: theme.strikethroughColor ?? theme.baseColor
            ], range: element.contentRange)
            
            for syntaxRange in element.syntaxRanges {
                guard syntaxRange.location + syntaxRange.length <= storage.length else { continue }
                storage.addAttributes([
                    .foregroundColor: NSColor.clear,
                    .font: NSFont.systemFont(ofSize: 0.1)
                ], range: syntaxRange)
            }
        }
    }
    
    // MARK: - Cursor & Line Tracking
    
    /// Update the current line range based on cursor position
    private func updateCurrentLineRange() {
        let text = storage.string as NSString
        guard cursorPosition <= text.length else {
            currentLineRange = NSRange(location: 0, length: 0)
            return
        }
        currentLineRange = text.lineRange(for: NSRange(location: cursorPosition, length: 0))
    }
    
    /// Update syntax visibility when cursor moves (show/hide markers)
    private func updateSyntaxVisibility() {
        guard !isProcessingEdits && !storage.string.isEmpty else { return }
        
        // Find which element the cursor is currently inside
        var currentElementIndex: Int? = nil
        for (index, element) in cachedElements.enumerated() {
            if cursorPosition >= element.range.location && 
               cursorPosition <= element.range.location + element.range.length {
                currentElementIndex = index
                break
            }
        }
        
        // If cursor didn't move to a different element, no update needed
        guard currentElementIndex != previousElementIndex else { return }
        
        beginEditing()
        
        var affectedRange: NSRange? = nil
        
        // Update the element cursor LEFT (if any)
        if let prevIndex = previousElementIndex, prevIndex < cachedElements.count {
            let element = cachedElements[prevIndex]
            applyBaseStyle(to: element.range)
            applyStyle(for: element)
            affectedRange = element.range
        }
        
        // Update the element cursor ENTERED (if any)
        if let currIndex = currentElementIndex {
            let element = cachedElements[currIndex]
            applyBaseStyle(to: element.range)
            applyStyle(for: element)
            if affectedRange == nil {
                affectedRange = element.range
            } else {
                affectedRange = NSUnionRange(affectedRange!, element.range)
            }
        }
        
        // Update tracking
        previousElementIndex = currentElementIndex
        
        if let range = affectedRange {
            edited(.editedAttributes, range: range, changeInLength: 0)
        }
        endEditing()
    }
    
    // MARK: - Public Methods
    
    /// Force a full re-parse and re-style (useful after loading new content)
    func refreshMarkdownStyling() {
        guard !storage.string.isEmpty else { return }
        
        beginEditing()
        
        let fullRange = NSRange(location: 0, length: storage.length)
        applyBaseStyle(to: fullRange)
        parseAndApplyMarkdown()
        
        edited(.editedAttributes, range: fullRange, changeInLength: 0)
        endEditing()
    }
    
    /// Update theme (will trigger re-styling)
    func updateTheme(_ newTheme: MarkdownTheme) {
        theme = newTheme
    }
}
