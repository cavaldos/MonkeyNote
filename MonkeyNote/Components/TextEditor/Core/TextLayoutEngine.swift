//
//  TextLayoutEngine.swift
//  MonkeyNote
//
//  Core layout engine using CoreText for efficient text layout.
//  Supports viewport-based layout for large documents and line caching.
//

#if os(macOS)
import Foundation
import CoreText
import AppKit

/// Configuration for text layout
struct TextLayoutConfig {
    var containerWidth: CGFloat = 800
    var containerHeight: CGFloat = .greatestFiniteMagnitude
    var lineSpacing: CGFloat = 0
    var paragraphSpacing: CGFloat = 0
    var textInsets: NSEdgeInsets = NSEdgeInsets(top: 8, left: 8, bottom: 8, right: 8)
    var lineHeightMultiplier: CGFloat = 1.0
    var wrapLines: Bool = true
}

/// Engine responsible for text layout using CoreText
final class TextLayoutEngine {
    
    // MARK: - Properties
    
    /// Layout configuration
    var config: TextLayoutConfig {
        didSet {
            invalidateAllLayout()
        }
    }
    
    /// The text storage to layout
    weak var textStorage: CoreTextStorage?
    
    /// Cached lines
    private var lineCache: [Int: TextLine] = [:]
    
    /// Line Y positions (cumulative heights)
    private var lineYPositions: [CGFloat] = []
    
    /// Line heights
    private var lineHeights: [CGFloat] = []
    
    /// Estimated line height (for fast scrolling)
    private var estimatedLineHeight: CGFloat = 20
    
    /// Whether layout is valid
    private(set) var isLayoutValid: Bool = false
    
    /// Total content height
    private(set) var contentHeight: CGFloat = 0
    
    /// Total content width (for horizontal scrolling if not wrapping)
    private(set) var contentWidth: CGFloat = 0
    
    /// Default font for layout
    var font: NSFont = .monospacedSystemFont(ofSize: 14, weight: .regular) {
        didSet {
            updateEstimatedLineHeight()
            invalidateAllLayout()
        }
    }
    
    // MARK: - Initialization
    
    init(config: TextLayoutConfig = TextLayoutConfig()) {
        self.config = config
        updateEstimatedLineHeight()
    }
    
    // MARK: - Layout Invalidation
    
    /// Invalidate all cached layout
    func invalidateAllLayout() {
        lineCache.removeAll()
        lineYPositions.removeAll()
        lineHeights.removeAll()
        isLayoutValid = false
        contentHeight = 0
    }
    
    /// Invalidate layout from a specific line
    /// - Parameter lineIndex: Starting line index
    func invalidateLayout(from lineIndex: Int) {
        // Remove cached lines from this index onwards
        for key in lineCache.keys where key >= lineIndex {
            lineCache.removeValue(forKey: key)
        }
        
        // Truncate Y positions array
        if lineIndex < lineYPositions.count {
            lineYPositions.removeSubrange(lineIndex...)
            lineHeights.removeSubrange(lineIndex...)
        }
        
        isLayoutValid = false
    }
    
    /// Invalidate layout for a range of text that changed
    /// - Parameters:
    ///   - range: Changed range
    ///   - delta: Change in length (positive for insert, negative for delete)
    func invalidateLayout(inRange range: NSRange, delta: Int) {
        guard let storage = textStorage else { return }
        
        // Find affected line
        let lineIndex = storage.lineIndex(for: range.location)
        
        // Invalidate from affected line onwards
        invalidateLayout(from: lineIndex)
    }
    
    // MARK: - Full Layout
    
    /// Perform full layout of the entire document
    func performFullLayout() {
        guard let storage = textStorage else {
            contentHeight = 0
            isLayoutValid = true
            return
        }
        
        // Clear caches
        lineCache.removeAll()
        lineYPositions.removeAll()
        lineHeights.removeAll()
        
        let attributedString = storage.attributedString
        guard attributedString.length > 0 else {
            contentHeight = config.textInsets.top + config.textInsets.bottom + estimatedLineHeight
            isLayoutValid = true
            return
        }
        
        // Create framesetter
        let framesetter = CTFramesetterCreateWithAttributedString(attributedString)
        
        // Calculate available width
        let availableWidth = config.containerWidth - config.textInsets.left - config.textInsets.right
        
        // Create typesetter for line-by-line layout
        let typesetter = CTTypesetterCreateWithAttributedString(attributedString)
        
        var currentY = config.textInsets.top
        var lineIndex = 0
        var currentPosition = 0
        let textLength = attributedString.length
        
        while currentPosition < textLength {
            // Get suggested line break
            let lineLength: Int
            if config.wrapLines {
                lineLength = CTTypesetterSuggestLineBreak(typesetter, currentPosition, Double(availableWidth))
            } else {
                // Find next newline or end of text
                let remainingRange = NSRange(location: currentPosition, length: textLength - currentPosition)
                let newlineRange = (attributedString.string as NSString).range(of: "\n", range: remainingRange)
                if newlineRange.location != NSNotFound {
                    lineLength = newlineRange.location - currentPosition + 1
                } else {
                    lineLength = textLength - currentPosition
                }
            }
            
            guard lineLength > 0 else { break }
            
            // Create CTLine
            let lineRange = CFRange(location: currentPosition, length: lineLength)
            let ctLine = CTTypesetterCreateLine(typesetter, lineRange)
            
            // Create TextLine
            let nsRange = NSRange(location: currentPosition, length: lineLength)
            let textLine = TextLine(
                ctLine: ctLine,
                index: lineIndex,
                range: nsRange,
                origin: CGPoint(x: config.textInsets.left, y: currentY)
            )
            
            // Apply line height multiplier
            let lineHeight = textLine.height * config.lineHeightMultiplier
            
            // Cache the line
            lineCache[lineIndex] = textLine
            lineYPositions.append(currentY)
            lineHeights.append(lineHeight)
            
            // Update max width
            contentWidth = max(contentWidth, textLine.width + config.textInsets.left + config.textInsets.right)
            
            // Move to next line
            currentY += lineHeight + config.lineSpacing
            currentPosition += lineLength
            lineIndex += 1
        }
        
        // Final content height
        contentHeight = currentY + config.textInsets.bottom
        isLayoutValid = true
    }
    
    // MARK: - Viewport-Based Layout
    
    /// Layout only lines visible in a viewport (with buffer)
    /// - Parameters:
    ///   - visibleRect: The visible rectangle
    ///   - bufferLines: Number of extra lines to layout above/below viewport
    /// - Returns: Array of lines to render
    func layoutVisibleLines(in visibleRect: CGRect, bufferLines: Int = 20) -> [TextLine] {
        guard let storage = textStorage else { return [] }
        
        // Ensure we have basic layout info
        if !isLayoutValid {
            performFullLayout()
        }
        
        // Find line range for visible rect
        let startLine = max(0, lineIndex(forY: visibleRect.minY) - bufferLines)
        let endLine = min(storage.lineCount - 1, lineIndex(forY: visibleRect.maxY) + bufferLines)
        
        guard startLine <= endLine else { return [] }
        
        var visibleLines: [TextLine] = []
        
        for index in startLine...endLine {
            if let cachedLine = lineCache[index] {
                visibleLines.append(cachedLine)
            } else {
                // Layout this specific line if not cached
                if let line = layoutLine(at: index) {
                    visibleLines.append(line)
                }
            }
        }
        
        return visibleLines
    }
    
    /// Layout a specific line
    /// - Parameter index: Line index
    /// - Returns: The laid out TextLine, or nil if index is invalid
    func layoutLine(at index: Int) -> TextLine? {
        guard let storage = textStorage else { return nil }
        
        // Check cache first
        if let cached = lineCache[index] {
            return cached
        }
        
        // Get line range from storage
        let range = storage.lineRange(for: index)
        guard range.location != NSNotFound else { return nil }
        
        // Get attributed substring for this line
        let attrString = storage.attributedString
        guard range.location + range.length <= attrString.length else { return nil }
        
        let lineAttrString = attrString.attributedSubstring(from: range)
        
        // Create CTLine
        let ctLine = CTLineCreateWithAttributedString(lineAttrString as CFAttributedString)
        
        // Calculate Y position
        let yPosition: CGFloat
        if index < lineYPositions.count {
            yPosition = lineYPositions[index]
        } else {
            // Estimate Y position
            yPosition = config.textInsets.top + CGFloat(index) * (estimatedLineHeight + config.lineSpacing)
        }
        
        // Create TextLine
        let textLine = TextLine(
            ctLine: ctLine,
            index: index,
            range: range,
            origin: CGPoint(x: config.textInsets.left, y: yPosition)
        )
        
        // Cache it
        lineCache[index] = textLine
        
        return textLine
    }
    
    // MARK: - Position Calculations
    
    /// Get line index for a Y coordinate
    /// - Parameter y: Y coordinate
    /// - Returns: Line index
    func lineIndex(forY y: CGFloat) -> Int {
        // Binary search if we have Y positions cached
        if !lineYPositions.isEmpty {
            var low = 0
            var high = lineYPositions.count - 1
            
            while low < high {
                let mid = (low + high + 1) / 2
                if lineYPositions[mid] <= y {
                    low = mid
                } else {
                    high = mid - 1
                }
            }
            return low
        }
        
        // Estimate based on average line height
        return max(0, Int((y - config.textInsets.top) / (estimatedLineHeight + config.lineSpacing)))
    }
    
    /// Get Y position for a line index
    /// - Parameter index: Line index
    /// - Returns: Y position
    func yPosition(forLine index: Int) -> CGFloat {
        if index < lineYPositions.count {
            return lineYPositions[index]
        }
        return config.textInsets.top + CGFloat(index) * (estimatedLineHeight + config.lineSpacing)
    }
    
    /// Get text position for a point
    /// - Parameter point: Point in content coordinates
    /// - Returns: Text position, or nil if point is outside content
    func textPosition(for point: CGPoint) -> TextPosition? {
        guard let storage = textStorage, storage.length > 0 else { return nil }
        
        let lineIdx = lineIndex(forY: point.y)
        
        guard let line = layoutLine(at: lineIdx) else {
            return TextPosition(offset: 0)
        }
        
        // Get position within line
        let localX = point.x - line.origin.x
        let charIndex = line.position(forX: localX)
        
        return TextPosition(offset: charIndex)
    }
    
    /// Get point for a text position (for cursor placement)
    /// - Parameter position: Text position
    /// - Returns: Point in content coordinates
    func point(for position: TextPosition) -> CGPoint? {
        guard let storage = textStorage else { return nil }
        
        let lineIdx = storage.lineIndex(for: position.offset)
        guard let line = layoutLine(at: lineIdx) else { return nil }
        
        let xOffset = line.xOffset(for: position.offset) ?? 0
        
        return CGPoint(
            x: line.origin.x + xOffset,
            y: line.origin.y
        )
    }
    
    /// Get cursor rectangle for a text position
    /// - Parameters:
    ///   - position: Text position
    ///   - cursorWidth: Width of the cursor
    /// - Returns: Cursor rectangle
    func cursorRect(for position: TextPosition, cursorWidth: CGFloat = 2) -> CGRect? {
        guard let storage = textStorage else { return nil }
        
        let lineIdx = storage.lineIndex(for: position.offset)
        guard let line = layoutLine(at: lineIdx) else { return nil }
        
        let xOffset = line.xOffset(for: position.offset) ?? 0
        
        return CGRect(
            x: line.origin.x + xOffset,
            y: line.origin.y,
            width: cursorWidth,
            height: line.height
        )
    }
    
    // MARK: - Selection Rectangles
    
    /// Get selection rectangles for a range
    /// - Parameter range: Selection range
    /// - Returns: Array of rectangles covering the selection
    func selectionRects(for range: TextRange) -> [CGRect] {
        guard let storage = textStorage else { return [] }
        
        let nsRange = range.nsRange
        guard nsRange.length > 0 else { return [] }
        
        var rects: [CGRect] = []
        
        let startLine = storage.lineIndex(for: nsRange.location)
        let endLine = storage.lineIndex(for: nsRange.location + nsRange.length)
        
        for lineIdx in startLine...endLine {
            guard let line = layoutLine(at: lineIdx) else { continue }
            
            let lineRects = line.selectionRects(for: nsRange)
            rects.append(contentsOf: lineRects)
        }
        
        return rects
    }
    
    // MARK: - Helpers
    
    /// Update estimated line height based on current font
    private func updateEstimatedLineHeight() {
        // Get font metrics
        let ascent = font.ascender
        let descent = -font.descender
        let leading = font.leading
        
        estimatedLineHeight = (ascent + descent + leading) * config.lineHeightMultiplier
    }
    
    /// Get line at a specific index
    /// - Parameter index: Line index
    /// - Returns: TextLine if available
    func line(at index: Int) -> TextLine? {
        layoutLine(at: index)
    }
    
    /// Get all cached lines
    var cachedLines: [TextLine] {
        Array(lineCache.values).sorted { $0.index < $1.index }
    }
}

// MARK: - CoreTextStorageDelegate

extension TextLayoutEngine: CoreTextStorageDelegate {
    func textStorage(_ storage: CoreTextStorage, didChangeInRange range: NSRange, changeInLength delta: Int) {
        invalidateLayout(inRange: range, delta: delta)
    }
}

#endif
