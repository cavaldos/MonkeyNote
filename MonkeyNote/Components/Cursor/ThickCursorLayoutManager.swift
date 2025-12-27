//
//  ThickCursorLayoutManager.swift
//  MonkeyNote
//
//  Created by Nguyen Ngoc Khanh on 24/12/25.
//

#if os(macOS)
import AppKit

class ThickCursorLayoutManager: NSLayoutManager {
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

            // Get bounding rect for this line
            self.enumerateEnclosingRects(forGlyphRange: glyphRange, withinSelectedGlyphRange: NSRange(location: NSNotFound, length: 0), in: textContainers.first!) { rect, _ in
                var barRect = rect
                barRect.origin.x = origin.x + 2  // Small offset from left edge
                barRect.origin.y += origin.y
                barRect.size.width = 3  // Bar width

                // Draw vertical bar
                let barColor = NSColor.gray
                let path = NSBezierPath(roundedRect: barRect, xRadius: 1.5, yRadius: 1.5)
                barColor.setFill()
                path.fill()
            }
        }
    }
}
#endif
