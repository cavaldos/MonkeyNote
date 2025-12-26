//
//  ThickCursorTextEditor.swift
//  Note
//
//  Created by Nguyen Ngoc Khanh on 24/12/25.
//

#if os(macOS)
import SwiftUI
import AppKit

// MARK: - Word Suggestion Manager
class WordSuggestionManager {
    static let shared = WordSuggestionManager()
    
    // HashSet for O(1) duplicate checking and existence lookup
    private var bundledWordSet: Set<String> = []
    private var customWordSet: Set<String> = []
    
    // Sorted arrays for O(log n) binary search with prefix matching
    private var bundledWordsSorted: [String] = []
    private var customWordsSorted: [String] = []
    private var allWordsSorted: [String] = []
    
    // Prefix cache for O(1) repeated queries (max 100 entries to prevent memory bloat)
    private var prefixCache: [String: [String]] = [:]
    private let maxCacheSize = 100
    
    private var customFolderURL: URL?
    private var useBuiltIn: Bool = true
    private var minWordLength: Int = 4
    
    private init() {
        loadBundledWords()
        loadCustomWordsFromUserDefaults()
        useBuiltIn = UserDefaults.standard.object(forKey: "note.useBuiltInDictionary") as? Bool ?? true
        minWordLength = UserDefaults.standard.object(forKey: "note.minWordLength") as? Int ?? 4
    }
    
    private func loadBundledWords() {
        // Load from bundled word.txt file
        if let path = Bundle.main.path(forResource: "word", ofType: "txt"),
           let content = try? String(contentsOfFile: path, encoding: .utf8) {
            let words = parseWords(from: content)
            bundledWordSet = Set(words) // O(n) - deduplicate automatically
            bundledWordsSorted = bundledWordSet.sorted() // O(n log n) - sort once
            rebuildCombinedWordList()
        }
    }
    
    private func loadCustomWordsFromUserDefaults() {
        // Load custom folder path from UserDefaults
        if let bookmarkData = UserDefaults.standard.data(forKey: "note.customWordFolderBookmark") {
            do {
                var isStale = false
                let url = try URL(resolvingBookmarkData: bookmarkData, options: .withSecurityScope, relativeTo: nil, bookmarkDataIsStale: &isStale)
                if url.startAccessingSecurityScopedResource() {
                    customFolderURL = url
                    loadCustomWords(from: url)
                }
            } catch {
                print("Failed to resolve bookmark: \(error)")
            }
        }
    }
    
    func setUseBuiltIn(_ value: Bool) {
        useBuiltIn = value
        rebuildCombinedWordList()
        clearCache()
    }
    
    func setMinWordLength(_ value: Int) {
        minWordLength = value
        clearCache()
    }
    
    func setCustomFolder(_ url: URL?) {
        // Stop accessing previous folder
        customFolderURL?.stopAccessingSecurityScopedResource()
        
        if let url = url {
            // Save bookmark for security-scoped access
            do {
                let bookmarkData = try url.bookmarkData(options: .withSecurityScope, includingResourceValuesForKeys: nil, relativeTo: nil)
                UserDefaults.standard.set(bookmarkData, forKey: "note.customWordFolderBookmark")
                customFolderURL = url
                loadCustomWords(from: url)
            } catch {
                print("Failed to create bookmark: \(error)")
            }
        } else {
            UserDefaults.standard.removeObject(forKey: "note.customWordFolderBookmark")
            customFolderURL = nil
            customWordSet = []
            customWordsSorted = []
            rebuildCombinedWordList()
            clearCache()
        }
    }
    
    func getCustomFolderURL() -> URL? {
        return customFolderURL
    }
    
    private func loadCustomWords(from folderURL: URL) {
        var tempWords: [String] = []
        
        let fileManager = FileManager.default
        guard let enumerator = fileManager.enumerator(at: folderURL, includingPropertiesForKeys: [.isRegularFileKey], options: [.skipsHiddenFiles]) else {
            return
        }
        
        for case let fileURL as URL in enumerator {
            if fileURL.pathExtension.lowercased() == "txt" {
                if let content = try? String(contentsOf: fileURL, encoding: .utf8) {
                    let words = parseWords(from: content)
                    tempWords.append(contentsOf: words)
                }
            }
        }
        
        // Use Set for automatic deduplication - O(n)
        customWordSet = Set(tempWords)
        customWordsSorted = customWordSet.sorted() // O(n log n) - sort once
        rebuildCombinedWordList()
        clearCache()
    }
    
    func reloadCustomWords() {
        if let url = customFolderURL {
            loadCustomWords(from: url)
        }
    }
    
    private func parseWords(from content: String) -> [String] {
        // Parse words separated by commas, newlines, and spaces
        return content
            .components(separatedBy: CharacterSet(charactersIn: ",\n "))
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty && $0.count >= 2 }
    }
    
    // Rebuild combined sorted word list when sources change
    private func rebuildCombinedWordList() {
        var combinedSet: Set<String> = []
        if useBuiltIn {
            combinedSet.formUnion(bundledWordSet)
        }
        combinedSet.formUnion(customWordSet)
        allWordsSorted = combinedSet.sorted() // O(n log n) - sort combined list once
    }
    
    // Clear prefix cache
    private func clearCache() {
        prefixCache.removeAll()
    }
    
    // OPTIMIZED: HashSet + Binary Search + Caching
    // Time complexity: O(log n + k) where k = number of matches (typically < 10)
    // Space complexity: O(n + c) where c = cache size (max 100)
    func getSuggestion(for prefix: String) -> String? {
        guard !prefix.isEmpty else { return nil }
        let lowercasedPrefix = prefix.lowercased()
        
        // Check cache first - O(1)
        if let cached = prefixCache[lowercasedPrefix] {
            // Return first match that meets minWordLength and isn't exact match
            return cached.first {
                $0.lowercased() != lowercasedPrefix && $0.count >= minWordLength
            }.map { word in
                // Return only completion part (without the prefix)
                let completionStartIndex = word.index(word.startIndex, offsetBy: prefix.count)
                return String(word[completionStartIndex...])
            }
        }
        
        // Binary search to find first word >= lowercasedPrefix - O(log n)
        var matches: [String] = []
        
        // Binary search for the starting position
        var left = 0
        var right = allWordsSorted.count
        while left < right {
            let mid = left + (right - left) / 2
            if allWordsSorted[mid].lowercased() < lowercasedPrefix {
                left = mid + 1
            } else {
                right = mid
            }
        }
        let startIndex = left
        
        // Linear scan from startIndex (very fast because sorted, typically finds match in < 10 iterations)
        for i in startIndex..<allWordsSorted.count {
            let word = allWordsSorted[i]
            let lowercasedWord = word.lowercased()
            
            if lowercasedWord.hasPrefix(lowercasedPrefix) {
                matches.append(word)
            } else {
                break // Stop when no longer matching prefix (early termination)
            }
        }
        
        // Cache the results (limit cache size to prevent memory bloat)
        if prefixCache.count >= maxCacheSize {
            // Remove oldest entry (simple FIFO, could use LRU for better performance)
            if let firstKey = prefixCache.keys.first {
                prefixCache.removeValue(forKey: firstKey)
            }
        }
        prefixCache[lowercasedPrefix] = matches
        
        // Return first match that meets criteria
        return matches.first {
            $0.lowercased() != lowercasedPrefix && $0.count >= minWordLength
        }.map { word in
            // Return only completion part (without the prefix)
            let completionStartIndex = word.index(word.startIndex, offsetBy: prefix.count)
            return String(word[completionStartIndex...])
        }
    }
    
    // MARK: - Sentence Suggestion (Beta)
    func getSentenceSuggestion() -> String {
        // TODO: Replace this with actual sentence suggestion logic
        // This is a placeholder for future development
        return "this is a test version of the sentence suggestion feature"
    }
    
    var customWordCount: Int {
        return customWordSet.count
    }
    
    var bundledWordCount: Int {
        return bundledWordSet.count
    }
}

private class ThickCursorLayoutManager: NSLayoutManager {
    var cursorWidth: CGFloat = 6
    
    // Custom attribute key for rounded background
    static let roundedBackgroundColorKey = NSAttributedString.Key("roundedBackgroundColor")
    // Custom attribute key for blockquote bar
    static let blockquoteBarKey = NSAttributedString.Key("blockquoteBar")
    
    override func drawBackground(forGlyphRange glyphsToShow: NSRange, at origin: NSPoint) {
        super.drawBackground(forGlyphRange: glyphsToShow, at: origin)
        
        guard let textStorage = textStorage else { return }
        
        let characterRange = self.characterRange(forGlyphRange: glyphsToShow, actualGlyphRange: nil)
        
        // Draw rounded backgrounds for inline code
        textStorage.enumerateAttribute(Self.roundedBackgroundColorKey, in: characterRange, options: []) { value, range, _ in
            guard let color = value as? NSColor else { return }
            
            let glyphRange = self.glyphRange(forCharacterRange: range, actualCharacterRange: nil)
            
            // Get all rects for this range (handles line wrapping)
            self.enumerateEnclosingRects(forGlyphRange: glyphRange, withinSelectedGlyphRange: NSRange(location: NSNotFound, length: 0), in: textContainers.first!) { rect, _ in
                var adjustedRect = rect
                adjustedRect.origin.x += origin.x
                adjustedRect.origin.y += origin.y
                
                // Add padding
                let horizontalPadding: CGFloat = 4
                let verticalPadding: CGFloat = 2
                adjustedRect.origin.x -= horizontalPadding
                adjustedRect.origin.y -= verticalPadding
                adjustedRect.size.width += horizontalPadding * 2
                adjustedRect.size.height += verticalPadding * 2
                
                // Draw rounded rectangle
                let path = NSBezierPath(roundedRect: adjustedRect, xRadius: 5, yRadius: 5)
                color.setFill()
                path.fill()
            }
        }
        
        // Draw vertical bar for blockquotes
        textStorage.enumerateAttribute(Self.blockquoteBarKey, in: characterRange, options: []) { value, range, _ in
            guard value != nil else { return }
            
            let glyphRange = self.glyphRange(forCharacterRange: range, actualCharacterRange: nil)
            
            // Get the bounding rect for this line
            self.enumerateEnclosingRects(forGlyphRange: glyphRange, withinSelectedGlyphRange: NSRange(location: NSNotFound, length: 0), in: textContainers.first!) { rect, _ in
                var barRect = rect
                barRect.origin.x = origin.x + 2  // Small offset from left edge
                barRect.origin.y += origin.y
                barRect.size.width = 3  // Bar width
                
                // Draw the vertical bar
                let barColor = NSColor.gray
                let path = NSBezierPath(roundedRect: barRect, xRadius: 1.5, yRadius: 1.5)
                barColor.setFill()
                path.fill()
            }
        }
    }
}

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
    }
    
    private func handleSlashCommand(_ command: SlashCommand) {
        guard let range = slashCommandRange else { return }
        
        // Delete the "/" character and insert the list prefix
        let text = self.string as NSString
        let lineRange = text.lineRange(for: range)
        let lineStart = lineRange.location
        
        // Replace from line start to after "/" with the command prefix
        let rangeToReplace = NSRange(location: lineStart, length: range.location + range.length - lineStart)
        replaceCharacters(in: rangeToReplace, with: command.prefix)
        
        let newCursorPosition = lineStart + command.prefix.utf16.count
        setSelectedRange(NSRange(location: newCursorPosition, length: 0))
        
        slashCommandRange = nil
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
                slashCommandController.selectCurrent()
                return
            case 53: // Escape
                dismissSlashMenu()
                return
            default:
                // Any other key dismisses menu
                dismissSlashMenu()
            }
        }
        
        // Handle Escape to dismiss autocomplete suggestion
        if event.keyCode == 53 { // Escape
            if currentSuggestion != nil {
                hideSuggestion()
                return
            }
        }
        
        guard !event.isARepeat else {
            super.keyDown(with: event)
            return
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
                            let rangeAfterChar = NSRange(location: prevCharIndex + 1, length: lineRange.location + lineRange.length - prevCharIndex - 1)
                            let remainingText = text.substring(with: rangeAfterChar)
                            
                            // Replace the entire line from dash/dot to end with bullet + remaining text
                            let lineAfterChar = NSRange(location: prevCharIndex, length: lineRange.location + lineRange.length - prevCharIndex)
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
                            let rangeAfterNumber = NSRange(location: prevCharIndex + 1, length: lineRange.location + lineRange.length - prevCharIndex - 1)
                            let remainingText = text.substring(with: rangeAfterNumber)
                            
                            // Replace the entire line from number to end with proper numbered list format
                            let lineAfterNumber = NSRange(location: prevCharIndex - 1, length: lineRange.location + lineRange.length - (prevCharIndex - 1))
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
                        
                        // Update cursor position in MarkdownTextStorage
                        if let textStorage = self.textStorage as? MarkdownTextStorage {
                            textStorage.cursorPosition = self.selectedRange().location
                        }
                        return
                    }
                }
            }
        }
        
        super.insertText(insertString, replacementRange: replacementRange)
        
        // Update cursor position in MarkdownTextStorage
        if let textStorage = self.textStorage as? MarkdownTextStorage {
            textStorage.cursorPosition = self.selectedRange().location
        }
        
        // Update autocomplete suggestion
        // Hide suggestion if space or punctuation is typed
        if str.rangeOfCharacter(from: CharacterSet.alphanumerics) == nil {
            hideSuggestion()
        } else {
            updateSuggestion()
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
            showSlashMenu()
        }
    }
    
    override func deleteBackward(_ sender: Any?) {
        super.deleteBackward(sender)
        
        // Update cursor position in MarkdownTextStorage
        if let textStorage = self.textStorage as? MarkdownTextStorage {
            textStorage.cursorPosition = self.selectedRange().location
        }
        
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
        
        // Update cursor position in MarkdownTextStorage for syntax visibility
        if let textStorage = self.textStorage as? MarkdownTextStorage {
            textStorage.cursorPosition = selectedRange.location
        }
        
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
        
        var newText = selectedText
        
        switch action {
        case .bold:
            newText = "**\(selectedText)**"
        case .italic:
            newText = "_\(selectedText)_"
        case .code:
            newText = "`\(selectedText)`"
        case .strikethrough:
            newText = "~~\(selectedText)~~"
        case .highlight:
            newText = "==\(selectedText)=="
        case .link:
            newText = "[\(selectedText)](url)"
        case .heading:
            // Add heading marker at the beginning of line
            let lineRange = text.lineRange(for: range)
            let lineStart = lineRange.location
            let currentLine = text.substring(with: lineRange)
            
            if currentLine.hasPrefix("### ") {
                // Remove heading
                performUndoableReplacement(in: NSRange(location: lineStart, length: 4), with: "")
            } else if currentLine.hasPrefix("## ") {
                // H2 -> H3
                performUndoableReplacement(in: NSRange(location: lineStart, length: 3), with: "### ")
            } else if currentLine.hasPrefix("# ") {
                // H1 -> H2
                performUndoableReplacement(in: NSRange(location: lineStart, length: 2), with: "## ")
            } else {
                // Add H1
                performUndoableReplacement(in: NSRange(location: lineStart, length: 0), with: "# ")
            }
            return
        case .list:
            // Add bullet at the beginning of line
            let lineRange = text.lineRange(for: range)
            let lineStart = lineRange.location
            let currentLine = text.substring(with: lineRange)
            
            if currentLine.hasPrefix("• ") || currentLine.hasPrefix("- ") {
                // Remove bullet
                performUndoableReplacement(in: NSRange(location: lineStart, length: 2), with: "")
            } else {
                // Add bullet
                performUndoableReplacement(in: NSRange(location: lineStart, length: 0), with: "• ")
            }
            return
        case .alignLeft:
            // Alignment is not typically supported in plain markdown
            return
        }
        
        // Replace selected text with formatted text (with undo support)
        performUndoableReplacement(in: range, with: newText)
        
        // Update cursor position
        let newCursorPosition = range.location + newText.utf16.count
        setSelectedRange(NSRange(location: newCursorPosition, length: 0))
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
        
        // Only update if search is active
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
    var markdownRenderEnabled: Bool = true
    var horizontalPadding: CGFloat = 0
    
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

        // Use MarkdownTextStorage for live markdown rendering
        let textStorage = MarkdownTextStorage()
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
        textView.isRichText = true  // Enable rich text for markdown styling
        textView.allowsUndo = true
        textView.isEditable = true
        textView.isSelectable = true
        textView.drawsBackground = false
        textView.textContainerInset = NSSize(width: horizontalPadding, height: 0)
        
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
        
        // Configure MarkdownTextStorage with base font and color
        textStorage.baseFont = font
        textStorage.baseTextColor = isDarkMode
            ? NSColor.white.withAlphaComponent(0.92)
            : NSColor.black.withAlphaComponent(0.92)
        textStorage.markdownRenderEnabled = markdownRenderEnabled
        
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
        
        // Trigger initial markdown processing
        textStorage.reprocessMarkdown()

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
            
            // Reprocess markdown when text changes externally
            if let textStorage = textView.textStorage as? MarkdownTextStorage {
                textStorage.reprocessMarkdown()
            }
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
        
        // Update MarkdownTextStorage settings
        if let textStorage = textView.textStorage as? MarkdownTextStorage {
            let needsReprocess = textStorage.baseFont != font || textStorage.baseTextColor != textColor || textStorage.markdownRenderEnabled != markdownRenderEnabled
            textStorage.baseFont = font
            textStorage.baseTextColor = textColor
            textStorage.markdownRenderEnabled = markdownRenderEnabled
            if needsReprocess {
                textStorage.reprocessMarkdown()
            }
        }

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
            
            // Update cursor position in MarkdownTextStorage
            if let textStorage = textView.textStorage as? MarkdownTextStorage {
                textStorage.cursorPosition = textView.selectedRange().location
            }
        }
        
        func textViewDidChangeSelection(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            
            // Update cursor position in MarkdownTextStorage for syntax visibility
            if let textStorage = textView.textStorage as? MarkdownTextStorage {
                textStorage.cursorPosition = textView.selectedRange().location
            }
        }
    }
}
#endif
