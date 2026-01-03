//
//  ThickCursorTextEditor.swift
//  MonkeyNote
//
//  Created by Nguyen Ngoc Khanh on 24/12/25.
//

#if os(macOS)
import SwiftUI
import AppKit
private class ThickCursorTextView: NSTextView {
    var cursorWidth: CGFloat = 6
    var cursorBlinkEnabled: Bool = true {
        didSet {
            if cursorBlinkEnabled != oldValue {
                if cursorBlinkEnabled {
                    startBlinkTimer()
                } else {
                    stopBlinkTimer()
                    cursorLayer?.opacity = 1
                }
            }
        }
    }
    var cursorAnimationEnabled: Bool = true
    var cursorAnimationDuration: Double = 0.15
    var searchText: String = ""
    var autocompleteEnabled: Bool = true
    var autocompleteDelay: Double = 0.0
    var autocompleteOpacity: Double = 0.5
    var suggestionMode: String = "word"  // "word" or "sentence"
    
    // Double-tap navigation
    var doubleTapNavigationEnabled: Bool = true
    var doubleTapDelay: Double = 300  // milliseconds
    private var lastKeyCode: UInt16 = 0
    private var lastKeyTime: Date = Date.distantPast
    
    // Search navigation
    var currentSearchIndex: Int = 0
    var onSearchMatchesChanged: ((Int, Bool) -> Void)?  // (count, isComplete)
    private var searchMatchRanges: [NSRange] = []  // All matches for navigation
    
    // Search optimization - viewport-based highlighting
    private var allMatchRanges: [NSRange] = []  // Full list from background search
    private var visibleHighlightedRanges: Set<Int> = []  // Indices of currently highlighted matches
    private var searchTask: Task<Void, Never>?  // Background search task
    private var isSearchComplete: Bool = false
    private var lastSearchQuery: String = ""
    private var lastVisibleRect: NSRect = .zero
    
    // Layer pooling for reuse
    private var layerPool: [CALayer] = []
    
    // Disable auto-scroll to cursor when typing
    var disableAutoScroll: Bool = false
    
    // Track if we're currently scrolling to prevent multiple scroll calls
    private var isScrolling: Bool = false
    
    private var cursorLayer: CALayer?
    private var lastCursorRect: NSRect = .zero
    private var highlightLayers: [CALayer] = []
    private var currentMatchLayers: [CALayer] = []  // Track current match layers for shake animation
    
    // Cursor blinking timer
    private var blinkTimer: Timer?
    private var cursorVisible: Bool = true
    
    // Slash command menu
    private var slashCommandController = SlashCommandWindowController()
    private var slashCommandRange: NSRange?
    private var slashFilterText: String = ""  // Track text typed after "/"
    
    // Dictionary lookup (triggered by "word\")
    private var dictionaryLookupController: DictionaryLookupWindowController?
    private var dictionaryLookupRange: NSRange?  // Range of "word\" including the backslash
    var dictionaryLanguage: String = "en"
    
    // Auto pair brackets/quotes
    var autoPairEnabled: Bool = true
    private let autoPairMap: [String: String] = [
        "\"": "\"",
        "'": "'",
        "(": ")",
        "[": "]",
        "{": "}",
        "`": "`"
    ]
    private let closingChars: Set<String> = ["\"", "'", ")", "]", "}", "`"]
    
    // Autocomplete ghost text
    private var ghostTextLayer: CATextLayer?
    private var currentSuggestion: String?
    private var suggestionWordStart: Int = 0
    private var suggestionTask: Task<Void, Never>?
    
    // Selection toolbar
    private var selectionToolbarController = SelectionToolbarController.shared
    
    // Flag to track if selection is from search navigation
    private var isNavigatingSearch: Bool = false
    
    deinit {
        stopBlinkTimer()
    }
    
    private func startBlinkTimer() {
        stopBlinkTimer()
        guard cursorBlinkEnabled else { return }
        
        cursorVisible = true
        blinkTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            self.cursorVisible.toggle()
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            self.cursorLayer?.opacity = self.cursorVisible ? 1 : 0
            CATransaction.commit()
        }
    }
    
    private func stopBlinkTimer() {
        blinkTimer?.invalidate()
        blinkTimer = nil
    }
    
    private func resetBlinkTimer() {
        // Reset the blink cycle - show cursor and restart timer
        cursorVisible = true
        cursorLayer?.opacity = 1
        if cursorBlinkEnabled {
            startBlinkTimer()
        }
    }
    
    override func becomeFirstResponder() -> Bool {
        let result = super.becomeFirstResponder()
        if result && cursorBlinkEnabled {
            startBlinkTimer()
        }
        return result
    }

    override func drawInsertionPoint(in rect: NSRect, color: NSColor, turnedOn flag: Bool) {
        // We handle blinking ourselves with the timer, so ignore the flag parameter
        var thickRect = rect
        thickRect.size.width = cursorWidth

        if cursorLayer == nil {
            let layer = CALayer()
            layer.cornerRadius = cursorWidth / 2
            layer.backgroundColor = color.cgColor
            wantsLayer = true
            self.layer?.addSublayer(layer)
            cursorLayer = layer
            
            // Start blink timer when cursor layer is created
            if cursorBlinkEnabled {
                startBlinkTimer()
            }
        }

        cursorLayer?.backgroundColor = color.cgColor
        cursorLayer?.cornerRadius = cursorWidth / 2

        if lastCursorRect != thickRect {
            if cursorAnimationEnabled {
                CATransaction.begin()
                CATransaction.setAnimationDuration(cursorAnimationDuration)
                CATransaction.setAnimationTimingFunction(CAMediaTimingFunction(name: .easeOut))
                cursorLayer?.frame = thickRect
                CATransaction.commit()
            } else {
                CATransaction.begin()
                CATransaction.setDisableActions(true)
                cursorLayer?.frame = thickRect
                CATransaction.commit()
            }
            lastCursorRect = thickRect
            // Reset blink when cursor moves
            resetBlinkTimer()
        }
    }

    override func setNeedsDisplay(_ invalidRect: NSRect, avoidAdditionalLayout flag: Bool) {
        var extendedRect = invalidRect
        extendedRect.size.width += cursorWidth
        super.setNeedsDisplay(extendedRect, avoidAdditionalLayout: flag)
    }

    override func resignFirstResponder() -> Bool {
        let didResign = super.resignFirstResponder()
        if didResign {
            stopBlinkTimer()
            cursorLayer?.opacity = 0
        }
        return didResign
    }

    override var rangeForUserCompletion: NSRange {
        selectedRange()
    }

    // MARK: - Search Highlighting (Viewport-Based Optimization)
    
    /// Main entry point - updates highlights based on current viewport
    func updateHighlights() {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        
        // If search query changed, reset everything and start fresh
        if query != lastSearchQuery {
            resetSearch()
            lastSearchQuery = query
        }
        
        guard !query.isEmpty, let layoutManager = layoutManager, let textContainer = textContainer else {
            clearAllHighlights()
            onSearchMatchesChanged?(0, true)
            return
        }
        
        let text = self.string
        guard !text.isEmpty else {
            clearAllHighlights()
            onSearchMatchesChanged?(0, true)
            return
        }
        
        // If we don't have all matches yet, perform background search first
        if !isSearchComplete && allMatchRanges.isEmpty {
            performFullSearch(query: query, in: text)
        }
        
        // Update visible highlights
        updateVisibleHighlights()
    }
    
    /// Perform full document search (synchronous for small docs, stored for navigation)
    private func performFullSearch(query: String, in text: String) {
        searchTask?.cancel()
        
        allMatchRanges.removeAll()
        searchMatchRanges.removeAll()
        
        var searchRange = NSRange(location: 0, length: text.utf16.count)
        
        while searchRange.location < text.utf16.count {
            let foundRange = (text as NSString).range(of: query, options: .caseInsensitive, range: searchRange)
            
            if foundRange.location == NSNotFound {
                break
            }
            
            guard foundRange.location + foundRange.length <= text.utf16.count else {
                break
            }
            
            allMatchRanges.append(foundRange)
            
            searchRange.location = foundRange.location + foundRange.length
            searchRange.length = text.utf16.count - searchRange.location
        }
        
        // Copy to searchMatchRanges for navigation
        searchMatchRanges = allMatchRanges
        isSearchComplete = true
        
        // Notify with final count
        onSearchMatchesChanged?(allMatchRanges.count, true)
    }
    
    /// Update highlights only for matches visible in viewport
    private func updateVisibleHighlights() {
        guard let layoutManager = layoutManager, let textContainer = textContainer else { return }
        
        let visibleRect = self.visibleRect
        
        // Skip if viewport hasn't changed significantly
        if abs(visibleRect.origin.y - lastVisibleRect.origin.y) < 10 &&
           abs(visibleRect.size.height - lastVisibleRect.size.height) < 10 &&
           !highlightLayers.isEmpty {
            // Just update current match highlighting
            updateCurrentMatchHighlight()
            return
        }
        lastVisibleRect = visibleRect
        
        // Recycle existing layers
        recycleAllHighlightLayers()
        
        // Get visible character range with buffer
        let glyphRange = layoutManager.glyphRange(forBoundingRect: visibleRect, in: textContainer)
        let visibleCharRange = layoutManager.characterRange(forGlyphRange: glyphRange, actualGlyphRange: nil)
        
        // Add buffer (half screen above and below)
        let bufferSize = visibleCharRange.length / 2
        let extendedStart = max(0, visibleCharRange.location - bufferSize)
        let extendedEnd = min(self.string.utf16.count, visibleCharRange.location + visibleCharRange.length + bufferSize)
        let extendedRange = NSRange(location: extendedStart, length: extendedEnd - extendedStart)
        
        // Ensure layout only for extended visible range
        layoutManager.ensureLayout(forCharacterRange: extendedRange)
        
        let origin = textContainerOrigin
        visibleHighlightedRanges.removeAll()
        
        // Only create layers for matches within extended visible range
        for (index, matchRange) in allMatchRanges.enumerated() {
            // Check if match overlaps with extended visible range
            let matchEnd = matchRange.location + matchRange.length
            let extendedEnd = extendedRange.location + extendedRange.length
            
            guard matchRange.location < extendedEnd && matchEnd > extendedRange.location else {
                continue
            }
            
            visibleHighlightedRanges.insert(index)
            
            let glyphRange = layoutManager.glyphRange(forCharacterRange: matchRange, actualCharacterRange: nil)
            guard glyphRange.location != NSNotFound else { continue }
            
            let isCurrentMatch = index == currentSearchIndex
            
            layoutManager.enumerateEnclosingRects(forGlyphRange: glyphRange, withinSelectedGlyphRange: NSRange(location: NSNotFound, length: 0), in: textContainer) { rect, _ in
                guard rect.width > 0 && rect.height > 0 else { return }
                
                let highlightLayer = self.reuseOrCreateLayer()
                let padding: CGFloat = isCurrentMatch ? 2.5 : 1.2
                let paddedRect = rect.insetBy(dx: -padding, dy: -padding)
                
                // Configure layer appearance
                CATransaction.begin()
                CATransaction.setDisableActions(true)
                
                if isCurrentMatch {
                    highlightLayer.backgroundColor = NSColor.orange.withAlphaComponent(0.6).cgColor
                    highlightLayer.borderWidth = 1.5
                    highlightLayer.borderColor = NSColor.orange.withAlphaComponent(0.8).cgColor
                    self.currentMatchLayers.append(highlightLayer)
                } else {
                    highlightLayer.backgroundColor = NSColor.yellow.withAlphaComponent(0.3).cgColor
                    highlightLayer.borderWidth = 0
                    highlightLayer.borderColor = nil
                }
                highlightLayer.cornerRadius = 3
                highlightLayer.frame = paddedRect.offsetBy(dx: origin.x, dy: origin.y)
                
                CATransaction.commit()
                
                self.layer?.addSublayer(highlightLayer)
                self.highlightLayers.append(highlightLayer)
            }
        }
    }
    
    /// Update only the current match highlight (for navigation without full redraw)
    private func updateCurrentMatchHighlight() {
        // Clear previous current match styling
        for layer in currentMatchLayers {
            layer.backgroundColor = NSColor.yellow.withAlphaComponent(0.3).cgColor
            layer.borderWidth = 0
            layer.borderColor = nil
        }
        currentMatchLayers.removeAll()
        
        // Find and update current match layer if visible
        guard currentSearchIndex < allMatchRanges.count,
              visibleHighlightedRanges.contains(currentSearchIndex),
              let layoutManager = layoutManager,
              let textContainer = textContainer else { return }
        
        let matchRange = allMatchRanges[currentSearchIndex]
        let glyphRange = layoutManager.glyphRange(forCharacterRange: matchRange, actualCharacterRange: nil)
        guard glyphRange.location != NSNotFound else { return }
        
        let origin = textContainerOrigin
        
        layoutManager.enumerateEnclosingRects(forGlyphRange: glyphRange, withinSelectedGlyphRange: NSRange(location: NSNotFound, length: 0), in: textContainer) { rect, _ in
            guard rect.width > 0 && rect.height > 0 else { return }
            
            // Find existing layer at this position or create new one
            let padding: CGFloat = 2.5
            let paddedRect = rect.insetBy(dx: -padding, dy: -padding)
            let targetFrame = paddedRect.offsetBy(dx: origin.x, dy: origin.y)
            
            // Look for existing layer at this position
            for layer in self.highlightLayers {
                if layer.frame.intersects(targetFrame) {
                    CATransaction.begin()
                    CATransaction.setDisableActions(true)
                    layer.backgroundColor = NSColor.orange.withAlphaComponent(0.6).cgColor
                    layer.borderWidth = 1.5
                    layer.borderColor = NSColor.orange.withAlphaComponent(0.8).cgColor
                    layer.frame = targetFrame
                    CATransaction.commit()
                    self.currentMatchLayers.append(layer)
                    return
                }
            }
        }
    }
    
    /// Clear all highlights and reset state
    private func clearAllHighlights() {
        recycleAllHighlightLayers()
        allMatchRanges.removeAll()
        searchMatchRanges.removeAll()
        visibleHighlightedRanges.removeAll()
        isSearchComplete = false
    }
    
    /// Reset search state (called when query changes)
    private func resetSearch() {
        searchTask?.cancel()
        clearAllHighlights()
        lastVisibleRect = .zero
    }
    
    // MARK: - Layer Pooling
    
    /// Get a layer from pool or create new one
    private func reuseOrCreateLayer() -> CALayer {
        if let layer = layerPool.popLast() {
            return layer
        }
        return CALayer()
    }
    
    /// Recycle all highlight layers back to pool
    private func recycleAllHighlightLayers() {
        for layer in highlightLayers {
            layer.removeFromSuperlayer()
            layerPool.append(layer)
        }
        highlightLayers.removeAll()
        currentMatchLayers.removeAll()
        
        // Limit pool size to prevent memory bloat
        if layerPool.count > 200 {
            layerPool.removeFirst(layerPool.count - 200)
        }
    }
    
    // Navigate to a specific search match by index
    func navigateToMatch(index: Int) {
        guard index >= 0 && index < searchMatchRanges.count else { return }
        
        let matchRange = searchMatchRanges[index]
        
        // Set flag before selecting to prevent toolbar from showing
        isNavigatingSearch = true
        
        // Select the match
        setSelectedRange(matchRange)
        
        // Reset flag
        isNavigatingSearch = false
        
        // Scroll to make it visible
        scrollRangeToVisible(matchRange)
        
        // Update highlights to show new current match
        currentSearchIndex = index
        updateHighlights()
        
        // Apply pulse animation to current match highlight
        pulseCurrentMatchHighlight()
    }
    
    // MARK: - Pulse Animation for Current Match (Scale up then back)
    private func pulseCurrentMatchHighlight() {
        // Apply pulse animation only to current match layers (orange ones)
        for layer in currentMatchLayers {
            // Set anchor point to center for proper scaling
            let bounds = layer.bounds
            layer.anchorPoint = CGPoint(x: 0.5, y: 0.5)
            layer.position = CGPoint(x: layer.frame.midX, y: layer.frame.midY)
            layer.bounds = bounds
            
            let scaleAnimation = CAKeyframeAnimation(keyPath: "transform.scale")
            scaleAnimation.values = [1.0, 1.2, 1.0]  // Normal → Scale up → Back to normal
            scaleAnimation.keyTimes = [0, 0.2, 0.4]
            scaleAnimation.timingFunctions = [
                CAMediaTimingFunction(name: .easeOut),      // Scale up quickly
                CAMediaTimingFunction(name: .easeInEaseOut) // Scale back smoothly
            ]
            scaleAnimation.duration = 0.25
            scaleAnimation.isRemovedOnCompletion = true
            layer.add(scaleAnimation, forKey: "pulse")
        }
    }
    
    // MARK: - Autocomplete Ghost Text
    private func updateSuggestion() {
        // Check if autocomplete is enabled
        guard autocompleteEnabled else {
            hideSuggestion()
            return
        }
        
        // Cancel any pending suggestion task
        suggestionTask?.cancel()
        
        // Hide ghost text immediately when user types (no delay for hiding)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        ghostTextLayer?.isHidden = true
        CATransaction.commit()
        
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
    
    private func performSuggestionUpdate() {
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
            currentSuggestion = suggestion
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
            currentSuggestion = suggestion
            suggestionWordStart = wordStart
            showGhostText(suggestion, at: cursorPosition)
        } else {
            hideSuggestion()
        }
    }
    
    private func showGhostText(_ text: String, at position: Int) {
        guard let layoutManager = layoutManager,
              let textContainer = textContainer else { return }
        
        // Get cursor position rect
        let glyphRange = layoutManager.glyphRange(forCharacterRange: NSRange(location: position, length: 0), actualCharacterRange: nil)
        var cursorRect = layoutManager.boundingRect(forGlyphRange: glyphRange, in: textContainer)
        cursorRect.origin.x += textContainerInset.width
        cursorRect.origin.y += textContainerInset.height
        
        // Create or update ghost text layer
        if ghostTextLayer == nil {
            let layer = CATextLayer()
            layer.contentsScale = NSScreen.main?.backingScaleFactor ?? 2.0
            layer.alignmentMode = .left
            wantsLayer = true
            self.layer?.addSublayer(layer)
            ghostTextLayer = layer
        }
        
        // Disable all animations for ghost text
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        
        // Configure the ghost text with opacity from settings
        let font = self.font ?? NSFont.systemFont(ofSize: 14)
        ghostTextLayer?.font = font
        ghostTextLayer?.fontSize = font.pointSize
        ghostTextLayer?.foregroundColor = NSColor.gray.withAlphaComponent(autocompleteOpacity).cgColor
        ghostTextLayer?.string = text
        
        // Calculate size for the ghost text
        let attributes: [NSAttributedString.Key: Any] = [.font: font]
        let textSize = (text as NSString).size(withAttributes: attributes)
        
        // Position ghost text right after cursor
        ghostTextLayer?.frame = NSRect(
            x: cursorRect.origin.x + cursorWidth,
            y: cursorRect.origin.y,
            width: textSize.width + 10,
            height: cursorRect.height
        )
        ghostTextLayer?.isHidden = false
        
        CATransaction.commit()
    }
    
    private func hideSuggestion() {
        suggestionTask?.cancel()
        
        // Disable animation when hiding
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        ghostTextLayer?.isHidden = true
        CATransaction.commit()
        
        currentSuggestion = nil
    }
    
    func acceptSuggestion() -> Bool {
        guard let suggestion = currentSuggestion, !suggestion.isEmpty else {
            return false
        }
        
        // Insert the suggestion at cursor position
        let selectedRange = self.selectedRange()
        replaceCharacters(in: selectedRange, with: suggestion)
        
        // Move cursor to end of inserted text
        let newPosition = selectedRange.location + suggestion.utf16.count
        setSelectedRange(NSRange(location: newPosition, length: 0))
        
        hideSuggestion()
        return true
    }
    
    // MARK: - Slash Command Menu
    private func showSlashMenu() {
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
    
    private func dismissSlashMenu() {
        slashCommandController.dismiss()
        slashCommandRange = nil
        slashFilterText = ""
    }
    
    private func handleSlashCommand(_ command: SlashCommand) {
        guard let range = slashCommandRange else { return }
        
        // Replace "/" and any filter text with the command prefix
        replaceCharacters(in: range, with: command.prefix)
        
        // Set cursor position right after the inserted prefix
        let newCursorPosition = range.location + command.prefix.utf16.count
        setSelectedRange(NSRange(location: newCursorPosition, length: 0))
        
        slashCommandRange = nil
        slashFilterText = ""
    }
    
    // MARK: - Dictionary Lookup (triggered by "word\")
    
    /// Called when "\" is typed - find the word before it and show lookup menu
    private func showDictionaryLookupForWordBeforeBackslash() {
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
    
    private func dismissDictionaryLookup() {
        dictionaryLookupController?.dismiss()
        dictionaryLookupRange = nil
    }

    override func keyDown(with event: NSEvent) {
        // Handle slash command menu navigation
        if slashCommandController.isVisible {
            switch event.keyCode {
            case 126: // Up arrow
                slashCommandController.moveUp()
                return
            case 125: // Down arrow
                slashCommandController.moveDown()
                return
            case 36: // Enter
                if slashCommandController.hasResults {
                    slashCommandController.selectCurrent()
                } else {
                    // No results, just dismiss and insert newline
                    dismissSlashMenu()
                    super.keyDown(with: event)
                }
                return
            case 53: // Escape
                dismissSlashMenu()
                return
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
                return
            default:
                // Let other keys (letters, etc.) pass through to insertText
                break
            }
        }
        
        // Handle dictionary lookup - dismiss on any key except viewing
        if let dictController = dictionaryLookupController, dictController.isVisible {
            // Escape dismisses the lookup
            if event.keyCode == 53 {
                dismissDictionaryLookup()
                return
            }
            // Any other key dismisses and continues normal behavior
            dismissDictionaryLookup()
        }
        
        // Handle Escape to dismiss autocomplete suggestion
        if event.keyCode == 53 { // Escape
            if currentSuggestion != nil {
                hideSuggestion()
                return
            }
        }
        
        // Handle formatting shortcuts (Cmd+B, Cmd+I, Cmd+E)
        if event.modifierFlags.contains(.command) {
            let selectedRange = self.selectedRange()
            if selectedRange.length > 0 {
                switch event.charactersIgnoringModifiers?.lowercased() {
                case "b":
                    applyFormatting(action: .bold, range: selectedRange)
                    return
                case "i":
                    applyFormatting(action: .italic, range: selectedRange)
                    return
                case "e":
                    applyFormatting(action: .code, range: selectedRange)
                    return
                default:
                    break
                }
            }
        }
        
        guard !event.isARepeat else {
            super.keyDown(with: event)
            return
        }
        
        // Handle double-tap navigation (Delete, Left Arrow, Right Arrow)
        if doubleTapNavigationEnabled {
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
                    return
                case 123: // Left Arrow - move to previous word (like Option+Left)
                    // First move undoes the character move by first tap
                    moveRight(nil)
                    moveWordLeft(nil)
                    return
                case 124: // Right Arrow - move to next word (like Option+Right)
                    // First move undoes the character move by first tap
                    moveLeft(nil)
                    moveWordRight(nil)
                    return
                default:
                    break
                }
            }
        }
        
        // Handle Tab key - check for autocomplete suggestion first
        if event.keyCode == 48 {
            // Try to accept autocomplete suggestion first
            if acceptSuggestion() {
                return
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
                                return
                            }
                            
                            let rangeAfterChar = NSRange(location: afterCharStart, length: afterCharLength)
                            let remainingText = text.substring(with: rangeAfterChar)
                            
                            // Replace the entire line from dash/dot to end of line content with bullet + remaining text
                            let lineAfterChar = NSRange(location: prevCharIndex, length: 1 + afterCharLength)
                            let newText = "• " + remainingText.trimmingCharacters(in: .whitespacesAndNewlines)
                            self.replaceCharacters(in: lineAfterChar, with: newText)
                            self.setSelectedRange(NSRange(location: prevCharIndex + newText.utf16.count, length: 0))
                            return
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
                                return
                            }
                            
                            let rangeAfterNumber = NSRange(location: afterNumberStart, length: afterNumberLength)
                            let remainingText = text.substring(with: rangeAfterNumber)
                            
                            // Replace the number pattern and remaining text on this line only
                            let lineAfterNumber = NSRange(location: prevCharIndex - 1, length: 2 + afterNumberLength)
                            let newText = twoCharsBefore + " " + remainingText.trimmingCharacters(in: .whitespacesAndNewlines)
                            self.replaceCharacters(in: lineAfterNumber, with: newText)
                            self.setSelectedRange(NSRange(location: prevCharIndex - 1 + newText.utf16.count, length: 0))
                            return
                        }
                    }
                }
            }
            
            super.insertText("\t")
            return
        }
        
        // Handle Shift + Enter - soft line break (continue same list item)
        if event.keyCode == 36 && event.modifierFlags.contains(.shift) {
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
                return
            }
            
            // Check if we're in a bullet list
            if trimmedLine.hasPrefix("•") {
                // Insert newline with indent (2 spaces to align with text after "• ")
                super.insertText("\n  ")
                return
            }
            
            // Default: just insert newline
            super.insertText("\n")
            return
        }
        
        if event.keyCode == 36 {
            let selectedRange = self.selectedRange()
            let text = self.string as NSString
            
            let lineRange = text.lineRange(for: selectedRange)
            let currentLine = text.substring(with: lineRange)
            let trimmedLine = currentLine.trimmingCharacters(in: .whitespaces)
            
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
                return
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
                return
            }
        }
        
        super.keyDown(with: event)
    }
    
    override func insertText(_ insertString: Any, replacementRange: NSRange) {
        guard let str = insertString as? String else {
            super.insertText(insertString, replacementRange: replacementRange)
            return
        }
        
        // If slash command menu is visible, update filter with typed character
        if slashCommandController.isVisible {
            // Only allow alphanumeric characters for filtering
            if str.rangeOfCharacter(from: CharacterSet.alphanumerics) != nil {
                slashFilterText += str
                slashCommandController.updateFilter(slashFilterText)
                super.insertText(insertString, replacementRange: replacementRange)
                
                // Update the slash command range to include filter text
                if let range = slashCommandRange {
                    slashCommandRange = NSRange(location: range.location, length: 1 + slashFilterText.utf16.count)
                }
                return
            } else if str == " " || str == "\n" || str == "\t" {
                // Space, newline, or tab dismisses the menu
                dismissSlashMenu()
                super.insertText(insertString, replacementRange: replacementRange)
                return
            } else {
                // Other special characters dismiss the menu
                dismissSlashMenu()
            }
        }
        
        // Check for space after "." or "-" at line start to convert to bullet
        if str == " " {
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
                        return
                    }
                }
            }
        }
        
        // MARK: - Auto Pair Brackets/Quotes
        if autoPairEnabled {
            let selectedRange = self.selectedRange()
            let text = self.string as NSString
            
            // Check if typing a closing character that already exists at cursor
            if closingChars.contains(str) && selectedRange.location < text.length {
                let nextChar = text.substring(with: NSRange(location: selectedRange.location, length: 1))
                if nextChar == str {
                    // Skip over the existing closing character instead of inserting
                    self.setSelectedRange(NSRange(location: selectedRange.location + 1, length: 0))
                    return
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
                            super.insertText(insertString, replacementRange: replacementRange)
                            
                            // Update autocomplete suggestion
                            hideSuggestion()
                            return
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
                    return
                }
                
                // Insert both opening and closing, position cursor in between
                let pairText = str + closingChar
                super.insertText(pairText, replacementRange: replacementRange)
                
                // Move cursor back by 1 to be between the pair
                let newPosition = self.selectedRange().location - 1
                self.setSelectedRange(NSRange(location: newPosition, length: 0))
                
                // Hide suggestion since we typed a special character
                hideSuggestion()
                return
            }
        }
        
        super.insertText(insertString, replacementRange: replacementRange)
        
        // Update autocomplete suggestion
        // Hide suggestion if space or punctuation is typed
        if str.rangeOfCharacter(from: CharacterSet.alphanumerics) == nil {
            hideSuggestion()
        } else {
            updateSuggestion()
        }
        
        // Check if "\" was typed - show dictionary lookup for word before it
        if str == "\\" {
            showDictionaryLookupForWordBeforeBackslash()
            return
        }
        
        // Check if "/" was typed at the beginning of a line
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
    
    override func deleteBackward(_ sender: Any?) {
        super.deleteBackward(sender)
        
        // Update suggestion after deletion
        updateSuggestion()
    }
    
    override func setSelectedRange(_ charRange: NSRange) {
        super.setSelectedRange(charRange)
        handleSelectionChange()
    }
    
    override func setSelectedRange(_ charRange: NSRange, affinity: NSSelectionAffinity, stillSelecting stillSelectingFlag: Bool) {
        super.setSelectedRange(charRange, affinity: affinity, stillSelecting: stillSelectingFlag)
        if !stillSelectingFlag {
            handleSelectionChange()
        }
    }
    
    private func handleSelectionChange() {
        let selectedRange = self.selectedRange()
        
        // Hide autocomplete suggestion when cursor moves
        hideSuggestion()
        
        // Show selection toolbar when there's a selection (but not during search navigation)
        if selectedRange.length > 0 && !isNavigatingSearch {
            showSelectionToolbar(for: selectedRange)
        } else {
            selectionToolbarController.dismiss()
        }
    }
    
    private func showSelectionToolbar(for range: NSRange) {
        guard let layoutManager = layoutManager,
              let textContainer = textContainer,
              let window = self.window else { return }
        
        // Get the rect of the selected text
        let glyphRange = layoutManager.glyphRange(forCharacterRange: range, actualCharacterRange: nil)
        var selectionRect = layoutManager.boundingRect(forGlyphRange: glyphRange, in: textContainer)
        selectionRect.origin.x += textContainerInset.width
        selectionRect.origin.y += textContainerInset.height
        
        // Convert to window coordinates
        let rectInView = convert(selectionRect, to: nil)
        let rectInScreen = window.convertToScreen(NSRect(
            origin: rectInView.origin,
            size: CGSize(width: selectionRect.width, height: selectionRect.height)
        ))
        
        // Position toolbar above the selection (centered)
        let toolbarPoint = NSPoint(
            x: rectInScreen.midX,
            y: rectInScreen.maxY
        )
        
        selectionToolbarController.show(
            at: toolbarPoint,
            in: window,
            selectionRange: range,
            onAction: { [weak self] (action: ToolbarAction, selectionRange: NSRange) in
                self?.applyFormatting(action: action, range: selectionRange)
            }
        )
    }
    
    private func applyFormatting(action: ToolbarAction, range: NSRange) {
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
    private func getMarkdownSyntax(for action: ToolbarAction) -> (prefix: String, suffix: String) {
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
    private func handleSpecialFormatting(action: ToolbarAction, range: NSRange, text: NSString) {
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
    private func performUndoableReplacement(in range: NSRange, with newText: String) {
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
    
    // MARK: - Link Handling
    
    override func clicked(onLink link: Any, at charIndex: Int) {
        // Handle link click manually to prevent errors
        guard let urlString = link as? String else { return }
        
        // Try to create URL and open it
        var urlToOpen: URL?
        
        if let url = URL(string: urlString) {
            // Check if URL has a scheme
            if url.scheme != nil {
                urlToOpen = url
            } else {
                // Add https:// if no scheme
                urlToOpen = URL(string: "https://\(urlString)")
            }
        }
        
        if let url = urlToOpen {
            NSWorkspace.shared.open(url)
        }
    }
    
    // Prevent default link behavior that causes errors
    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        let charIndex = characterIndexForInsertion(at: point)
        
        // Check if clicked on a link
        if charIndex < textStorage?.length ?? 0,
           let attrs = textStorage?.attributes(at: charIndex, effectiveRange: nil),
           let link = attrs[.link] {
            clicked(onLink: link, at: charIndex)
            return
        }
        
        super.mouseDown(with: event)
    }
    
    override func layout() {
        super.layout()
        
        // Only update search highlights if search is active
        guard !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        
        // Debounce scroll updates to prevent excessive redraws
        NSObject.cancelPreviousPerformRequests(withTarget: self, selector: #selector(debouncedUpdateHighlights), object: nil)
        perform(#selector(debouncedUpdateHighlights), with: nil, afterDelay: 0.03)
    }
    
    @objc private func debouncedUpdateHighlights() {
        updateHighlights()
    }
    
    // Override to prevent flickering when scrolling to cursor
    override func scrollRangeToVisible(_ range: NSRange) {
        // Prevent multiple rapid scroll calls that cause flickering
        guard !isScrolling else { return }
        
        isScrolling = true
        super.scrollRangeToVisible(range)
        
        // Reset flag after a short delay to batch scroll requests
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
            self?.isScrolling = false
        }
    }
}

struct ThickCursorTextEditor: NSViewRepresentable {
    @Binding var text: String
    var isDarkMode: Bool
    var cursorWidth: CGFloat
    var cursorBlinkEnabled: Bool
    var cursorAnimationEnabled: Bool
    var cursorAnimationDuration: Double
    var fontSize: Double
    var fontFamily: String
    var searchText: String
    var autocompleteEnabled: Bool
    var autocompleteDelay: Double
    var autocompleteOpacity: Double
    var suggestionMode: String
    var horizontalPadding: CGFloat = 0
    
    // Double-tap navigation
    var doubleTapNavigationEnabled: Bool = true
    var doubleTapDelay: Double = 300
    
    // Search navigation
    var currentSearchIndex: Int = 0
    var onSearchMatchesChanged: ((Int, Bool) -> Void)? = nil  // Reports (count, isComplete)
    var onNavigateToMatch: ((Int) -> Void)? = nil  // Called when should navigate to specific match

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.borderType = .noBorder
        scrollView.drawsBackground = false

        let layoutManager = ThickCursorLayoutManager()
        layoutManager.cursorWidth = cursorWidth

        // Use standard NSTextStorage (no markdown rendering)
        let textStorage = NSTextStorage()
        textStorage.addLayoutManager(layoutManager)

        let textContainer = NSTextContainer()
        textContainer.widthTracksTextView = true
        textContainer.containerSize = NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude)
        layoutManager.addTextContainer(textContainer)

        let textView = ThickCursorTextView(frame: .zero, textContainer: textContainer)
        textView.cursorWidth = cursorWidth
        textView.cursorBlinkEnabled = cursorBlinkEnabled
        textView.cursorAnimationEnabled = cursorAnimationEnabled
        textView.cursorAnimationDuration = cursorAnimationDuration
        textView.searchText = searchText
        textView.currentSearchIndex = currentSearchIndex
        textView.onSearchMatchesChanged = onSearchMatchesChanged
        textView.autocompleteEnabled = autocompleteEnabled
        textView.autocompleteDelay = autocompleteDelay
        textView.autocompleteOpacity = autocompleteOpacity
        textView.suggestionMode = suggestionMode
        textView.doubleTapNavigationEnabled = doubleTapNavigationEnabled
        textView.doubleTapDelay = doubleTapDelay
        textView.isRichText = false  // Plain text mode
        textView.allowsUndo = true
        textView.isEditable = true
        textView.isSelectable = true
        textView.drawsBackground = false
        textView.textContainerInset = NSSize(width: horizontalPadding, height: 0)
        
        // Disable automatic text substitution features
        textView.isAutomaticQuoteSubstitutionEnabled = false // disable "smart quotes"
        textView.isAutomaticDashSubstitutionEnabled = false // disable — em dash substitution
        textView.isAutomaticTextReplacementEnabled = false // disable text replacement (e.g., (c) → ©)
        textView.isAutomaticSpellingCorrectionEnabled = true // enable spelling correction
        textView.smartInsertDeleteEnabled = true // enable smart insert/delete

        
        // Critical settings for proper scrolling
        textView.minSize = NSSize(width: 0, height: 0)
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]

        let font: NSFont
        switch fontFamily {
        case "rounded":
            font = NSFont.systemFont(ofSize: fontSize, weight: .regular)
        case "serif":
            font = NSFont(name: "Times New Roman", size: fontSize) ?? NSFont.systemFont(ofSize: fontSize, weight: .regular)
        default:
            if let customFont = NSFont(name: fontFamily, size: fontSize) {
                font = customFont
            } else {
                font = NSFont.monospacedSystemFont(ofSize: fontSize, weight: .regular)
            }
        }
        textView.font = font
        
        textView.textColor = isDarkMode
            ? NSColor.white.withAlphaComponent(0.92)
            : NSColor.black.withAlphaComponent(0.92)
        textView.insertionPointColor = NSColor(
            red: 222.0 / 255.0,
            green: 99.0 / 255.0,
            blue: 74.0 / 255.0,
            alpha: 1.0
        )

        textView.delegate = context.coordinator
        textView.string = text

        scrollView.documentView = textView
        context.coordinator.textView = textView

        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? ThickCursorTextView else { return }

        if textView.string != text {
            let selectedRange = textView.selectedRange()
            textView.string = text
            let safeLocation = min(selectedRange.location, text.utf16.count)
            let safeLength = min(selectedRange.length, text.utf16.count - safeLocation)
            textView.setSelectedRange(NSRange(location: safeLocation, length: safeLength))
        }

        textView.cursorWidth = cursorWidth
        textView.cursorBlinkEnabled = cursorBlinkEnabled
        textView.cursorAnimationEnabled = cursorAnimationEnabled
        textView.cursorAnimationDuration = cursorAnimationDuration
        textView.searchText = searchText
        textView.currentSearchIndex = currentSearchIndex
        textView.onSearchMatchesChanged = onSearchMatchesChanged
        textView.autocompleteEnabled = autocompleteEnabled
        textView.autocompleteDelay = autocompleteDelay
        textView.autocompleteOpacity = autocompleteOpacity
        textView.suggestionMode = suggestionMode
        textView.doubleTapNavigationEnabled = doubleTapNavigationEnabled
        textView.doubleTapDelay = doubleTapDelay
        if let layoutManager = textView.layoutManager as? ThickCursorLayoutManager {
            layoutManager.cursorWidth = cursorWidth
        }

        let font: NSFont
        switch fontFamily {
        case "rounded":
            font = NSFont.systemFont(ofSize: fontSize, weight: .regular)
        case "serif":
            font = NSFont(name: "Times New Roman", size: fontSize) ?? NSFont.systemFont(ofSize: fontSize, weight: .regular)
        default:
            if let customFont = NSFont(name: fontFamily, size: fontSize) {
                font = customFont
            } else {
                font = NSFont.monospacedSystemFont(ofSize: fontSize, weight: .regular)
            }
        }
        textView.font = font
        
        let textColor = isDarkMode
            ? NSColor.white.withAlphaComponent(0.92)
            : NSColor.black.withAlphaComponent(0.92)

        textView.textColor = textColor
        textView.insertionPointColor = NSColor(
            red: 222.0 / 255.0,
            green: 99.0 / 255.0,
            blue: 74.0 / 255.0,
            alpha: 1.0
        )

        // Check if search index changed and navigate to match
        let previousIndex = context.coordinator.lastSearchIndex
        if currentSearchIndex != previousIndex && !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            context.coordinator.lastSearchIndex = currentSearchIndex
            // Need to update highlights first to populate searchMatchRanges
            textView.updateHighlights()
            // Then navigate to the match
            textView.navigateToMatch(index: currentSearchIndex)
        } else {
            textView.updateHighlights()
        }
    }

    class Coordinator: NSObject, NSTextViewDelegate {
        var parent: ThickCursorTextEditor
        fileprivate weak var textView: ThickCursorTextView?
        var lastSearchIndex: Int = 0

        init(_ parent: ThickCursorTextEditor) {
            self.parent = parent
            super.init()
            
            // Listen for focusEditor notification
            NotificationCenter.default.addObserver(
                self,
                selector: #selector(focusEditor),
                name: Notification.Name("focusEditor"),
                object: nil
            )
        }
        
        deinit {
            NotificationCenter.default.removeObserver(self)
        }
        
        @objc func focusEditor() {
            DispatchQueue.main.async {
                self.textView?.window?.makeFirstResponder(self.textView)
            }
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            parent.text = textView.string
        }
        
        func textViewDidChangeSelection(_ notification: Notification) {
            // No action needed - cursor position tracking removed with markdown rendering
        }
    }
}
#endif
