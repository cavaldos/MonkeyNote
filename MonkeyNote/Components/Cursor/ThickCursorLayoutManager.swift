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
    // Custom attribute key for horizontal rule
    static let horizontalRuleKey = NSAttributedString.Key("horizontalRule")
    // Custom attribute key for callout
    static let calloutKey = NSAttributedString.Key("callout")

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
        
        // Draw horizontal rule (divider)
        textStorage.enumerateAttribute(Self.horizontalRuleKey, in: characterRange, options: []) { value, range, _ in
            guard value != nil else { return }
            
            let glyphRange = self.glyphRange(forCharacterRange: range, actualCharacterRange: nil)
            guard let textContainer = textContainers.first else { return }
            
            // Get bounding rect for this line
            self.enumerateEnclosingRects(forGlyphRange: glyphRange, withinSelectedGlyphRange: NSRange(location: NSNotFound, length: 0), in: textContainer) { rect, _ in
                // Calculate horizontal line position (centered vertically in the line)
                let lineHeight: CGFloat = 1.5
                let lineY = rect.origin.y + origin.y + (rect.height / 2) - (lineHeight / 2)
                
                // Full width of text container
                let lineRect = NSRect(
                    x: origin.x,
                    y: lineY,
                    width: textContainer.size.width,
                    height: lineHeight
                )
                
                // Draw horizontal line with 30% opacity gray
                let lineColor = NSColor.gray.withAlphaComponent(0.3)
                let path = NSBezierPath(roundedRect: lineRect, xRadius: 0.75, yRadius: 0.75)
                lineColor.setFill()
                path.fill()
            }
        }
        
        // Draw callout background and left bar
        textStorage.enumerateAttribute(Self.calloutKey, in: characterRange, options: []) { value, range, _ in
            guard value != nil else { return }
            
            let glyphRange = self.glyphRange(forCharacterRange: range, actualCharacterRange: nil)
            guard let textContainer = textContainers.first else { return }
            
            // Get bounding rect for this line
            self.enumerateEnclosingRects(forGlyphRange: glyphRange, withinSelectedGlyphRange: NSRange(location: NSNotFound, length: 0), in: textContainer) { rect, _ in
                // Draw background (full width, subtle gray, rounded corners)
                // Only add small padding, don't extend into next line's space
                var bgRect = rect
                bgRect.origin.x = origin.x
                bgRect.origin.y += origin.y
                bgRect.size.width = textContainer.size.width
                
                // Minimal vertical padding - stay strictly within line bounds
                // No extra padding to avoid overlapping with adjacent lines
                let topPadding: CGFloat = 2
                let bottomPadding: CGFloat = 2
                // bgRect.origin.y -= topPadding
                // bgRect.size.height += topPadding
                
                let bgColor = NSColor.gray.withAlphaComponent(0.12)
                let bgPath = NSBezierPath(roundedRect: bgRect, xRadius: 6, yRadius: 6)
                bgColor.setFill()
                bgPath.fill()
                
                // Draw left bar (positioned at left edge of background)
                var barRect = bgRect
                barRect.size.width = 4
                
                let barColor = NSColor.gray.withAlphaComponent(0.5)
                let barPath = NSBezierPath(roundedRect: barRect, xRadius: 2, yRadius: 2)
                barColor.setFill()
                barPath.fill()
            }
        }
    }
}
#endif
