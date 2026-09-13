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
            if oldValue != baseFont {
                invalidateBaseStyleCache()
                reprocessMarkdown()
            }
        }
    }
    
    var baseTextColor: NSColor = .labelColor {
        didSet {
            if oldValue != baseTextColor {
                reprocessMarkdown()
            }
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
            guard oldValue != cursorPosition else { return }

            if isViewportMode {
                scheduleSyntaxVisibilityUpdate()
            } else {
                updateSyntaxVisibility(from: appliedCursorPosition, to: cursorPosition)
                appliedCursorPosition = cursorPosition
            }
        }
    }
    
    // Track if we're currently processing to avoid recursion
    private var isProcessing = false
    
    // Cache parsed matches for performance
    private var cachedMatches: [MarkdownMatch] = []
    private var lastParsedString: String = ""
    
    // MARK: - Debounce Properties
    private var debounceTimer: Timer?
    private let debounceDelay: TimeInterval = 0.15 // 150ms delay for full re-parse
    private var pendingEditedRange: NSRange?
    private var hasPendingFullParse: Bool = false
    private var syntaxVisibilityWorkItem: DispatchWorkItem?
    private let syntaxVisibilityDebounceDelay: TimeInterval = 0.08
    private var appliedCursorPosition: Int = 0
    
    // MARK: - Viewport-based Rendering (for large documents)
    // Threshold for switching to viewport-based mode (characters)
    private let largeDocumentThreshold: Int = 10_000
    
    // Current visible range (updated by text view)
    private var visibleRange: NSRange = NSRange(location: 0, length: 0)
    
    // Extended range with buffer for smooth scrolling
    private var extendedRange: NSRange = NSRange(location: 0, length: 0)
    
    // Buffer size above/below visible area (lines)
    private let viewportBufferLines: Int = 120
    
    // Minimum change threshold before re-parsing (characters)
    private let viewportChangeThreshold: Int = 2500
    
    // Track if using viewport mode
    private var isViewportMode: Bool {
        return backingStore.length > largeDocumentThreshold
    }

    var isLargeDocument: Bool {
        isViewportMode
    }
    
    // Cache matches only for extended range in viewport mode
    private var viewportMatches: [MarkdownMatch] = []
    
    // Track last styled range to avoid redundant work
    private var lastStyledRange: NSRange = NSRange(location: 0, length: 0)

    private var cachedBaseParagraphStyle: NSParagraphStyle?
    private var cachedBaseParagraphStylePointSize: CGFloat = 0
    private let paragraphSpacingFactor: CGFloat = 0.28
    private let minParagraphSpacing: CGFloat = 4
    private let maxParagraphSpacing: CGFloat = 16

    deinit {
        debounceTimer?.invalidate()
        syntaxVisibilityWorkItem?.cancel()
    }

    private func invalidateBaseStyleCache() {
        cachedBaseParagraphStyle = nil
        cachedBaseParagraphStylePointSize = 0
    }

    private var baseParagraphStyle: NSParagraphStyle {
        if let cachedBaseParagraphStyle,
           cachedBaseParagraphStylePointSize == baseFont.pointSize {
            return cachedBaseParagraphStyle
        }

        let paragraphStyle = NSMutableParagraphStyle()
        let computedSpacing = round(baseFont.pointSize * paragraphSpacingFactor)
        paragraphStyle.paragraphSpacing = min(max(computedSpacing, minParagraphSpacing), maxParagraphSpacing)
        paragraphStyle.paragraphSpacingBefore = 0
        paragraphStyle.lineSpacing = 0
        paragraphStyle.lineBreakMode = .byWordWrapping

        cachedBaseParagraphStyle = paragraphStyle
        cachedBaseParagraphStylePointSize = baseFont.pointSize
        return paragraphStyle
    }

    private var baseAttributes: [NSAttributedString.Key: Any] {
        [
            .font: baseFont,
            .foregroundColor: baseTextColor,
            .paragraphStyle: baseParagraphStyle
        ]
    }
    
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
        // Store the edited range for processing
        let editedRange = self.editedRange
        let changeInLength = self.changeInLength
        
        // Cancel any pending debounce timer
        debounceTimer?.invalidate()
        
        // Apply immediate markdown styling to the edited line only (no flicker)
        if !isProcessing && backingStore.length > 0 && markdownRenderEnabled {
            isProcessing = true
            let isLargeBulkEdit = isViewportMode && (abs(changeInLength) > 256 || editedRange.length > 256)

            if isLargeBulkEdit {
                // Avoid expensive whole-document parsing during large updates.
                applyBaseStylingToRange(editedRange)
            } else {
                applyImmediateMarkdownStyling(editedRange: editedRange, changeInLength: changeInLength)
            }
            isProcessing = false
        } else if !isProcessing && backingStore.length > 0 {
            // Markdown disabled - just apply base styling to new characters
            applyBaseStylingToRange(editedRange)
        }
        
        // Schedule debounced full markdown processing for complex cases
        // (multi-line edits, paste operations, etc.)
        hasPendingFullParse = true
        pendingEditedRange = editedRange
        
        debounceTimer = Timer.scheduledTimer(withTimeInterval: debounceDelay, repeats: false) { [weak self] _ in
            self?.performDebouncedProcessing()
        }
        
        super.processEditing()
    }
    
    // MARK: - Debounced Processing
    
    private func performDebouncedProcessing() {
        guard hasPendingFullParse, !isProcessing, backingStore.length > 0 else { return }

        // In viewport mode we wait for a valid visible range before re-parsing,
        // otherwise opening large files can trigger an expensive full-document parse.
        if isViewportMode && extendedRange.length == 0 {
            hasPendingFullParse = false
            pendingEditedRange = nil
            return
        }
        
        isProcessing = true
        hasPendingFullParse = false
        
        beginEditing()
        
        // Use incremental parsing if we have a specific edited range
        if let editedRange = pendingEditedRange {
            applyIncrementalMarkdownStyling(editedRange: editedRange)
        } else {
            applyFullMarkdownStyling()
        }
        
        pendingEditedRange = nil
        
        let updateRange: NSRange
        if isViewportMode, extendedRange.length > 0 {
            updateRange = extendedRange
        } else {
            updateRange = NSRange(location: 0, length: backingStore.length)
        }
        if updateRange.length > 0 {
            edited(.editedAttributes, range: updateRange, changeInLength: 0)
        }
        
        endEditing()
        
        isProcessing = false
    }
    
    // MARK: - Apply Base Styling (Fast, for immediate feedback)
    
    private func applyBaseStylingToRange(_ range: NSRange) {
        guard range.location + range.length <= backingStore.length else { return }
        
        // Only apply to the specific range, not the entire line
        guard range.length > 0 else { return }
        
        // Apply base styling only - no markdown parsing
        backingStore.setAttributes(baseAttributes, range: range)
    }
    
    // MARK: - Immediate Markdown Styling (No Flicker)
    
    /// Apply markdown styling immediately to the edited line without causing flicker.
    /// This preserves existing styling and only updates what's necessary.
    private func applyImmediateMarkdownStyling(editedRange: NSRange, changeInLength: Int) {
        guard backingStore.length > 0 else { return }
        
        let text = backingStore.string as NSString
        
        // Get the line range that contains the edit
        let lineRange = text.lineRange(for: editedRange)
        guard lineRange.location + lineRange.length <= backingStore.length else { return }
        
        // For single character insertions (typical typing), use smart incremental update
        if changeInLength == 1 && editedRange.length == 1 {
            // Apply base styling only to the new character
            backingStore.setAttributes(baseAttributes, range: editedRange)
            
            // Re-parse and apply styling to the current line only
            let lineText = text.substring(with: lineRange)
            let localMatches = parser.parse(lineText)
            
            // Apply styling to matches within this line
            for match in localMatches {
                let globalRange = NSRange(
                    location: match.range.location + lineRange.location,
                    length: match.range.length
                )
                let globalContentRange = NSRange(
                    location: match.contentRange.location + lineRange.location,
                    length: match.contentRange.length
                )
                let globalSyntaxRanges = match.syntaxRanges.map { syntaxRange in
                    NSRange(
                        location: syntaxRange.location + lineRange.location,
                        length: syntaxRange.length
                    )
                }
                
                // Validate ranges
                guard globalRange.location + globalRange.length <= backingStore.length,
                      globalContentRange.location + globalContentRange.length <= backingStore.length else {
                    continue
                }
                
                let globalMatch = MarkdownMatch(
                    range: globalRange,
                    contentRange: globalContentRange,
                    style: match.style,
                    syntaxRanges: globalSyntaxRanges,
                    url: match.url
                )
                
                applyMatchStyling(globalMatch, cursorInRange: isCursorInMatch(globalMatch))
            }
            
            // Update cached matches for this line
            updateCachedMatchesForLine(lineRange: lineRange, newMatches: localMatches)
            
        } else if changeInLength < 0 {
            // Deletion: re-parse the affected line
            let lineText = text.substring(with: lineRange)
            
            // Reset the line to base styling first
            backingStore.setAttributes(baseAttributes, range: lineRange)
            
            // Re-parse and apply
            let localMatches = parser.parse(lineText)
            for match in localMatches {
                let globalMatch = offsetMatch(match, by: lineRange.location)
                guard globalMatch.range.location + globalMatch.range.length <= backingStore.length else { continue }
                applyMatchStyling(globalMatch, cursorInRange: isCursorInMatch(globalMatch))
            }
            
            updateCachedMatchesForLine(lineRange: lineRange, newMatches: localMatches)
            
        } else {
            // Multi-character insertion (paste): apply base styling and re-parse
            let affectedRange = NSRange(location: editedRange.location, length: editedRange.length)
            guard affectedRange.location + affectedRange.length <= backingStore.length else { return }
            
            // Get expanded paragraph range for multi-line pastes
            let paragraphRange = text.paragraphRange(for: affectedRange)
            guard paragraphRange.location + paragraphRange.length <= backingStore.length else { return }
            
            // Reset and re-parse
            backingStore.setAttributes(baseAttributes, range: paragraphRange)
            
            let paragraphText = text.substring(with: paragraphRange)
            let localMatches = parser.parse(paragraphText)
            
            for match in localMatches {
                let globalMatch = offsetMatch(match, by: paragraphRange.location)
                guard globalMatch.range.location + globalMatch.range.length <= backingStore.length else { continue }
                applyMatchStyling(globalMatch, cursorInRange: isCursorInMatch(globalMatch))
            }
        }
    }
    
    /// Offset a match's ranges by a given amount
    private func offsetMatch(_ match: MarkdownMatch, by offset: Int) -> MarkdownMatch {
        return MarkdownMatch(
            range: NSRange(location: match.range.location + offset, length: match.range.length),
            contentRange: NSRange(location: match.contentRange.location + offset, length: match.contentRange.length),
            style: match.style,
            syntaxRanges: match.syntaxRanges.map { NSRange(location: $0.location + offset, length: $0.length) },
            url: match.url
        )
    }
    
    /// Update cached matches for a specific line
    private func updateCachedMatchesForLine(lineRange: NSRange, newMatches: [MarkdownMatch]) {
        // Remove old matches that overlap with this line
        cachedMatches.removeAll { match in
            NSIntersectionRange(match.range, lineRange).length > 0
        }
        
        // Add new matches with global positions
        for match in newMatches {
            let globalMatch = offsetMatch(match, by: lineRange.location)
            cachedMatches.append(globalMatch)
        }
        
        // Keep sorted
        cachedMatches.sort { $0.range.location < $1.range.location }
    }
    
    // MARK: - Incremental Markdown Styling
    
    private func applyIncrementalMarkdownStyling(editedRange: NSRange) {
        guard backingStore.length > 0 else { return }
        
        // For large documents in viewport mode, only style extended range
        if isViewportMode && extendedRange.length > 0 {
            applyViewportMarkdownStyling()
            return
        }
        
        let text = backingStore.string as NSString
        
        // Find affected paragraphs
        let affectedParagraphRange = text.paragraphRange(for: editedRange)
        
        // For small documents or large edits, do full parse
        if backingStore.length < 5000 || affectedParagraphRange.length > backingStore.length / 2 {
            applyFullMarkdownStyling()
            return
        }
        
        // Reset base styling for affected paragraph(s)
        backingStore.setAttributes(baseAttributes, range: affectedParagraphRange)
        
        // Parse only the affected paragraph(s)
        let affectedText = text.substring(with: affectedParagraphRange)
        let localMatches = parser.parse(affectedText)
        
        // Adjust match ranges to global positions and apply styling
        for match in localMatches {
            // Offset ranges to global position
            let globalRange = NSRange(
                location: match.range.location + affectedParagraphRange.location,
                length: match.range.length
            )
            let globalContentRange = NSRange(
                location: match.contentRange.location + affectedParagraphRange.location,
                length: match.contentRange.length
            )
            let globalSyntaxRanges = match.syntaxRanges.map { syntaxRange in
                NSRange(
                    location: syntaxRange.location + affectedParagraphRange.location,
                    length: syntaxRange.length
                )
            }
            
            let globalMatch = MarkdownMatch(
                range: globalRange,
                contentRange: globalContentRange,
                style: match.style,
                syntaxRanges: globalSyntaxRanges,
                url: match.url
            )
            
            applyMatchStyling(globalMatch, cursorInRange: isCursorInMatch(globalMatch))
        }
        
        // Update cached matches - remove old matches in affected range and add new ones
        cachedMatches.removeAll { match in
            NSIntersectionRange(match.range, affectedParagraphRange).length > 0
        }
        
        // Add new matches with global positions
        for match in localMatches {
            let globalMatch = MarkdownMatch(
                range: NSRange(location: match.range.location + affectedParagraphRange.location, length: match.range.length),
                contentRange: NSRange(location: match.contentRange.location + affectedParagraphRange.location, length: match.contentRange.length),
                style: match.style,
                syntaxRanges: match.syntaxRanges.map { NSRange(location: $0.location + affectedParagraphRange.location, length: $0.length) },
                url: match.url
            )
            cachedMatches.append(globalMatch)
        }
        
        // Re-sort cached matches
        cachedMatches.sort { $0.range.location < $1.range.location }
        lastParsedString = string
    }
    
    // MARK: - Full Markdown Styling
    
    private func applyFullMarkdownStyling() {
        guard backingStore.length > 0 else { return }
        
        let fullRange = NSRange(location: 0, length: backingStore.length)
        
        // Reset all attributes to base
        backingStore.setAttributes(baseAttributes, range: fullRange)
        
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

        appliedCursorPosition = cursorPosition
    }
    
    // MARK: - Apply Styling to Single Match
    
    private func applyMatchStyling(_ match: MarkdownMatch, cursorInRange: Bool) {
        // Validate ranges
        guard match.range.location + match.range.length <= backingStore.length,
              match.contentRange.location + match.contentRange.length <= backingStore.length else {
            return
        }
        
        // For todo list, render checkbox and apply strikethrough for checked items
        if case .todoUnchecked = match.style {
            // Use a condensed font so "- [ ]" takes up roughly the same width as "• "
            let compactFont = NSFont.systemFont(ofSize: baseFont.pointSize * 0.38)
            let todoAttributes: [NSAttributedString.Key: Any] = [
                .font: compactFont,
                .foregroundColor: NSColor.clear,
                NSAttributedString.Key("todoUnchecked"): true
            ]
            backingStore.addAttributes(todoAttributes, range: match.range)
            return
        }
        
        if case .todoChecked = match.style {
            let compactFont = NSFont.systemFont(ofSize: baseFont.pointSize * 0.38)
            let todoAttributes: [NSAttributedString.Key: Any] = [
                .font: compactFont,
                .foregroundColor: NSColor.clear,
                NSAttributedString.Key("todoChecked"): true
            ]
            backingStore.addAttributes(todoAttributes, range: match.range)
            
            // Apply strikethrough and dimmed color to the rest of the line after the marker
            let text = backingStore.string as NSString
            let lineRange = text.lineRange(for: match.range)
            let contentStart = match.range.location + match.range.length
            let contentLength = (lineRange.location + lineRange.length) - contentStart
            if contentLength > 0 {
                let contentRange = NSRange(location: contentStart, length: contentLength)
                guard contentRange.location + contentRange.length <= backingStore.length else { return }
                backingStore.addAttributes([
                    .strikethroughStyle: NSUnderlineStyle.single.rawValue,
                    .strikethroughColor: NSColor.gray.withAlphaComponent(0.6),
                    .foregroundColor: NSColor.gray
                ], range: contentRange)
            }
            return
        }
        
        // For bullet list, check if it's a dash that needs to be rendered as bullet
        if case .bulletList = match.style {
            let matchText = (backingStore.string as NSString).substring(with: match.range)
            if matchText == "- " {
                // Replace "- " with "• " visually by hiding the dash and showing bullet
                // We'll use a special attribute to render bullet instead
                let bulletAttributes: [NSAttributedString.Key: Any] = [
                    .font: baseFont,
                    .foregroundColor: NSColor(red: 0.7, green: 0.4, blue: 0.9, alpha: 1.0), // Purple
                    NSAttributedString.Key("renderAsBullet"): true
                ]
                backingStore.addAttributes(bulletAttributes, range: match.range)
                return
            }
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
        updateSyntaxVisibility(from: appliedCursorPosition, to: cursorPosition)
        appliedCursorPosition = cursorPosition
    }

    private func scheduleSyntaxVisibilityUpdate() {
        syntaxVisibilityWorkItem?.cancel()

        let oldPosition = appliedCursorPosition
        let newPosition = cursorPosition

        let workItem = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.updateSyntaxVisibility(from: oldPosition, to: newPosition)
            self.appliedCursorPosition = newPosition
        }

        syntaxVisibilityWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + syntaxVisibilityDebounceDelay, execute: workItem)
    }

    private func updateSyntaxVisibility(from oldPosition: Int, to newPosition: Int) {
        // Skip syntax visibility updates if markdown rendering is disabled
        guard markdownRenderEnabled, !isProcessing, backingStore.length > 0 else { return }

        let sourceMatches = isViewportMode ? viewportMatches : cachedMatches
        guard !sourceMatches.isEmpty else { return }

        let affectedMatches = sourceMatches.filter { match in
            matchContainsCursor(match, position: oldPosition) || matchContainsCursor(match, position: newPosition)
        }

        guard !affectedMatches.isEmpty else { return }

        isProcessing = true

        beginEditing()

        for match in affectedMatches {
            updateMatchSyntaxVisibility(match)
        }

        if let updateRange = combinedSyntaxRange(for: affectedMatches) {
            edited(.editedAttributes, range: updateRange, changeInLength: 0)
        }

        endEditing()

        isProcessing = false
    }

    private func matchContainsCursor(_ match: MarkdownMatch, position: Int) -> Bool {
        guard position >= 0 else { return false }
        return position >= match.range.location && position <= match.range.location + match.range.length
    }

    private func combinedSyntaxRange(for matches: [MarkdownMatch]) -> NSRange? {
        var minLocation = Int.max
        var maxEnd = 0

        for match in matches {
            for syntaxRange in match.syntaxRanges {
                guard syntaxRange.length > 0 else { continue }
                minLocation = min(minLocation, syntaxRange.location)
                maxEnd = max(maxEnd, syntaxRange.location + syntaxRange.length)
            }
        }

        guard minLocation != Int.max, maxEnd > minLocation else { return nil }
        return NSRange(location: minLocation, length: maxEnd - minLocation)
    }
    
    /// Update syntax visibility for a single match
    private func updateMatchSyntaxVisibility(_ match: MarkdownMatch) {
        guard match.range.location + match.range.length <= backingStore.length else { return }
        
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
    
    // MARK: - Full Reprocess
    
    func reprocessMarkdown() {
        guard backingStore.length > 0 else { return }

        syntaxVisibilityWorkItem?.cancel()
        
        isProcessing = true
        
        beginEditing()

        let fullRange = NSRange(location: 0, length: backingStore.length)

        // For large documents with unknown viewport, defer heavy parsing until
        // updateVisibleRange() provides a concrete visible range.
        if isViewportMode && extendedRange.length == 0 {
            backingStore.setAttributes(baseAttributes, range: fullRange)
            viewportMatches = []
            cachedMatches = []
            lastParsedString = string
        } else if isViewportMode && extendedRange.length > 0 {
            applyViewportMarkdownStyling()
        } else {
            applyFullMarkdownStyling()
        }
        
        let updateRange: NSRange
        if isViewportMode, extendedRange.length > 0 {
            updateRange = extendedRange
        } else {
            updateRange = fullRange
        }
        if updateRange.length > 0 {
            edited(.editedAttributes, range: updateRange, changeInLength: 0)
        }
        
        endEditing()
        
        isProcessing = false
        appliedCursorPosition = cursorPosition
    }
    
    // MARK: - Viewport-based Rendering
    
    /// Update the visible range - called by text view when scrolling
    /// - Parameter newVisibleRange: The character range currently visible in the viewport
    func updateVisibleRange(_ newVisibleRange: NSRange) {
        visibleRange = newVisibleRange
        
        // For small documents, use full parsing (faster for small docs)
        guard isViewportMode else { return }
        
        let text = backingStore.string as NSString
        let visibleLineRange = text.lineRange(for: newVisibleRange)
        guard visibleLineRange.length > 0 else { return }
        
        // Calculate extended range with buffer above and below (by lines)
        var extendedStart = visibleLineRange.location
        var linesAbove = 0
        while linesAbove < viewportBufferLines && extendedStart > 0 {
            let prevLocation = max(0, extendedStart - 1)
            let prevLineRange = text.lineRange(for: NSRange(location: prevLocation, length: 0))
            if prevLineRange.location == extendedStart { break }
            extendedStart = prevLineRange.location
            linesAbove += 1
        }
        
        var extendedEnd = visibleLineRange.location + visibleLineRange.length
        var linesBelow = 0
        while linesBelow < viewportBufferLines && extendedEnd < backingStore.length {
            let nextLocation = min(extendedEnd, max(0, backingStore.length - 1))
            let nextLineRange = text.lineRange(for: NSRange(location: nextLocation, length: 0))
            let nextEnd = nextLineRange.location + nextLineRange.length
            if nextEnd == extendedEnd { break }
            extendedEnd = nextEnd
            linesBelow += 1
        }
        
        let newExtendedRange = NSRange(location: extendedStart, length: extendedEnd - extendedStart)
        
        // Skip if range hasn't changed significantly (avoid excessive re-parsing)
        let locationChange = abs(extendedRange.location - newExtendedRange.location)
        let lengthChange = abs(extendedRange.length - newExtendedRange.length)

        let requiresInitialStyling = extendedRange.length == 0 || viewportMatches.isEmpty
        if !requiresInitialStyling && locationChange < viewportChangeThreshold && lengthChange < viewportChangeThreshold {
            return
        }
        
        extendedRange = newExtendedRange
        
        // Re-parse and style the new viewport
        guard !isProcessing else { return }
        
        isProcessing = true
        beginEditing()
        
        applyViewportMarkdownStyling()
        
        edited(.editedAttributes, range: extendedRange, changeInLength: 0)
        endEditing()
        
        isProcessing = false
    }
    
    /// Apply markdown styling only to the extended viewport range
    private func applyViewportMarkdownStyling() {
        guard backingStore.length > 0, extendedRange.length > 0 else { return }
        guard markdownRenderEnabled else {
            // Just apply base styling to extended range
            applyBaseStylingToRange(extendedRange)
            viewportMatches = []
            return
        }
        
        let text = backingStore.string as NSString
        
        // Expand to paragraph boundaries for correct parsing
        let paragraphRange = text.paragraphRange(for: extendedRange)
        
        // Validate range
        guard paragraphRange.location + paragraphRange.length <= backingStore.length else { return }
        
        // Reset base styling for extended range
        backingStore.setAttributes(baseAttributes, range: paragraphRange)
        
        // Parse only the visible portion
        let visibleText = text.substring(with: paragraphRange)
        let localMatches = parser.parse(visibleText)
        
        // Clear viewport matches and rebuild
        viewportMatches.removeAll()
        viewportMatches.reserveCapacity(localMatches.count)
        
        // Apply styling to matches within viewport
        for match in localMatches {
            // Offset ranges to global position
            let globalRange = NSRange(
                location: match.range.location + paragraphRange.location,
                length: match.range.length
            )
            let globalContentRange = NSRange(
                location: match.contentRange.location + paragraphRange.location,
                length: match.contentRange.length
            )
            let globalSyntaxRanges = match.syntaxRanges.map { syntaxRange in
                NSRange(
                    location: syntaxRange.location + paragraphRange.location,
                    length: syntaxRange.length
                )
            }
            
            let globalMatch = MarkdownMatch(
                range: globalRange,
                contentRange: globalContentRange,
                style: match.style,
                syntaxRanges: globalSyntaxRanges,
                url: match.url
            )
            
            viewportMatches.append(globalMatch)
            applyMatchStyling(globalMatch, cursorInRange: isCursorInMatch(globalMatch))
        }
        
        lastStyledRange = paragraphRange
        appliedCursorPosition = cursorPosition
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
