//
//  SearchHighlighting.swift
//  MonkeyNote
//
//  Extension for search text highlighting with viewport-based optimization
//

#if os(macOS)
import AppKit

// MARK: - Search Highlighting (Viewport-Based Optimization)
extension CursorTextView {
    
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
    func performFullSearch(query: String, in text: String) {
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
    func updateVisibleHighlights() {
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
            let extendedEndLoc = extendedRange.location + extendedRange.length
            
            guard matchRange.location < extendedEndLoc && matchEnd > extendedRange.location else {
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
    func updateCurrentMatchHighlight() {
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
    func clearAllHighlights() {
        recycleAllHighlightLayers()
        allMatchRanges.removeAll()
        searchMatchRanges.removeAll()
        visibleHighlightedRanges.removeAll()
        isSearchComplete = false
    }
    
    /// Reset search state (called when query changes)
    func resetSearch() {
        searchTask?.cancel()
        clearAllHighlights()
        lastVisibleRect = .zero
    }
    
    // MARK: - Layer Pooling
    
    /// Get a layer from pool or create new one
    func reuseOrCreateLayer() -> CALayer {
        if let layer = layerPool.popLast() {
            return layer
        }
        return CALayer()
    }
    
    /// Recycle all highlight layers back to pool
    func recycleAllHighlightLayers() {
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
}
#endif
