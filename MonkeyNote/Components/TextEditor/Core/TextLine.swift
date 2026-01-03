//
//  TextLine.swift
//  MonkeyNote
//
//  Represents a single line of text with layout information.
//  Used by TextLayoutEngine for efficient line-based rendering.
//

#if os(macOS)
import Foundation
import CoreText
import AppKit

/// Represents a single line of text with its layout information
final class TextLine {
    
    // MARK: - Core Properties
    
    /// The CoreText line object
    let ctLine: CTLine
    
    /// Line index (0-based)
    let index: Int
    
    /// Character range this line covers in the text storage
    let range: NSRange
    
    /// Origin point for drawing (in view coordinates, top-left origin)
    var origin: CGPoint
    
    // MARK: - Typographic Metrics
    
    /// Distance from baseline to top of line
    private(set) var ascent: CGFloat = 0
    
    /// Distance from baseline to bottom of line
    private(set) var descent: CGFloat = 0
    
    /// Extra space between lines
    private(set) var leading: CGFloat = 0
    
    /// Width of the line content
    private(set) var width: CGFloat = 0
    
    // MARK: - Computed Properties
    
    /// Total height of the line
    var height: CGFloat {
        ascent + descent + leading
    }
    
    /// Bounding rectangle for the line
    var bounds: CGRect {
        CGRect(
            x: origin.x,
            y: origin.y,
            width: width,
            height: height
        )
    }
    
    /// Baseline Y position
    var baseline: CGFloat {
        origin.y + ascent
    }
    
    /// Y position of the bottom of the line
    var bottom: CGFloat {
        origin.y + height
    }
    
    // MARK: - Initialization
    
    /// Create a TextLine from a CTLine
    /// - Parameters:
    ///   - ctLine: The CoreText line
    ///   - index: Line index
    ///   - range: Character range in the text storage
    ///   - origin: Origin point for drawing
    init(ctLine: CTLine, index: Int, range: NSRange, origin: CGPoint = .zero) {
        self.ctLine = ctLine
        self.index = index
        self.range = range
        self.origin = origin
        
        // Get typographic metrics
        width = CGFloat(CTLineGetTypographicBounds(ctLine, &ascent, &descent, &leading))
    }
    
    // MARK: - Position Calculations
    
    /// Get the X offset for a character position within this line
    /// - Parameter position: Character position (absolute in text storage)
    /// - Returns: X offset from line origin, or nil if position not in this line
    func xOffset(for position: Int) -> CGFloat? {
        guard range.contains(position) || position == range.location + range.length else {
            return nil
        }
        
        let localPosition = position - range.location
        let offset = CTLineGetOffsetForStringIndex(ctLine, localPosition + range.location, nil)
        return offset
    }
    
    /// Get the character position for an X coordinate
    /// - Parameter x: X coordinate relative to line origin
    /// - Returns: Character position (absolute in text storage)
    func position(forX x: CGFloat) -> Int {
        let index = CTLineGetStringIndexForPosition(ctLine, CGPoint(x: x, y: 0))
        if index == kCFNotFound {
            return range.location
        }
        return index
    }
    
    /// Get the character index closest to a point
    /// - Parameter point: Point relative to line origin
    /// - Returns: Closest character position
    func closestPosition(to point: CGPoint) -> Int {
        let index = CTLineGetStringIndexForPosition(ctLine, point)
        if index == kCFNotFound {
            // Return end of line if past the end
            return point.x >= width ? range.location + range.length : range.location
        }
        return index
    }
    
    /// Check if a point is within this line's bounds
    /// - Parameter point: Point in view coordinates
    /// - Returns: True if point is within bounds
    func containsPoint(_ point: CGPoint) -> Bool {
        bounds.contains(point)
    }
    
    /// Check if this line is visible in a given rect
    /// - Parameter rect: Visible rect
    /// - Returns: True if any part of the line is visible
    func isVisible(in rect: CGRect) -> Bool {
        bounds.intersects(rect)
    }
    
    // MARK: - Glyph Information
    
    /// Get the glyph runs for this line
    var glyphRuns: [CTRun] {
        CTLineGetGlyphRuns(ctLine) as? [CTRun] ?? []
    }
    
    /// Get the number of glyphs in this line
    var glyphCount: Int {
        CTLineGetGlyphCount(ctLine)
    }
    
    /// Check if this line has right-to-left text
    var hasRTLText: Bool {
        for run in glyphRuns {
            let status = CTRunGetStatus(run)
            if status.contains(.rightToLeft) {
                return true
            }
        }
        return false
    }
    
    // MARK: - Selection Rectangles
    
    /// Get selection rectangle for a range within this line
    /// - Parameter selectionRange: Selection range (absolute positions)
    /// - Returns: Array of rectangles covering the selection
    func selectionRects(for selectionRange: NSRange) -> [CGRect] {
        // Calculate intersection with this line
        let lineEnd = range.location + range.length
        let selectionEnd = selectionRange.location + selectionRange.length
        
        let intersectStart = max(range.location, selectionRange.location)
        let intersectEnd = min(lineEnd, selectionEnd)
        
        guard intersectStart < intersectEnd else { return [] }
        
        // Get X positions for start and end
        let startX = xOffset(for: intersectStart) ?? 0
        let endX = xOffset(for: intersectEnd) ?? width
        
        let rect = CGRect(
            x: origin.x + startX,
            y: origin.y,
            width: endX - startX,
            height: height
        )
        
        return [rect]
    }
    
    // MARK: - Drawing
    
    /// Draw the line in a graphics context
    /// - Parameters:
    ///   - context: The graphics context
    ///   - flipY: Whether to flip Y coordinate for CoreText (default true)
    func draw(in context: CGContext, flipY: Bool = true) {
        context.saveGState()
        
        if flipY {
            // CoreText uses bottom-left origin, convert from top-left
            context.textPosition = CGPoint(x: origin.x, y: origin.y + ascent)
        } else {
            context.textPosition = origin
        }
        
        CTLineDraw(ctLine, context)
        
        context.restoreGState()
    }
}

// MARK: - Line Fragment

/// Represents a fragment of a line (for wrapped lines)
struct LineFragment {
    let line: TextLine
    let fragmentIndex: Int
    let range: NSRange
    let origin: CGPoint
    let width: CGFloat
    
    var bounds: CGRect {
        CGRect(x: origin.x, y: origin.y, width: width, height: line.height)
    }
}

// MARK: - Debug

#if DEBUG
extension TextLine: CustomDebugStringConvertible {
    var debugDescription: String {
        "TextLine(index: \(index), range: \(range), origin: \(origin), size: \(width)x\(height))"
    }
}
#endif

#endif
