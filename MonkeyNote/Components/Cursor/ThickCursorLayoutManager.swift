//
//  CursorLayoutManager.swift
//  MonkeyNote
//
//  Created by Nguyen Ngoc Khanh on 24/12/25.
//

#if os(macOS)
import AppKit

class CursorLayoutManager: NSLayoutManager {
    var cursorWidth: CGFloat = 6

    // Custom attribute key for rounded background
    static let roundedBackgroundColorKey = NSAttributedString.Key("roundedBackgroundColor")
    // Custom attribute key for blockquote bar
    static let blockquoteBarKey = NSAttributedString.Key("blockquoteBar")
    // Custom attribute key for horizontal rule
    static let horizontalRuleKey = NSAttributedString.Key("horizontalRule")
    // Custom attribute key for callout
    static let calloutKey = NSAttributedString.Key("callout")
    // Custom attribute key for rendering dash as bullet
    static let renderAsBulletKey = NSAttributedString.Key("renderAsBullet")
    // Custom attribute keys for todo checkboxes
    static let todoUncheckedKey = NSAttributedString.Key("todoUnchecked")
    static let todoCheckedKey = NSAttributedString.Key("todoChecked")
    
    // MARK: - Draw Glyphs (for bullet and checkbox rendering)
    
    enum CustomGlyphType {
        case bullet
        case todoUnchecked
        case todoChecked
    }
    
    override func drawGlyphs(forGlyphRange glyphsToShow: NSRange, at origin: NSPoint) {
        guard let textStorage = textStorage else {
            super.drawGlyphs(forGlyphRange: glyphsToShow, at: origin)
            return
        }
        
        let characterRange = self.characterRange(forGlyphRange: glyphsToShow, actualGlyphRange: nil)
        
        // Find ranges that need custom glyph rendering
        var customRanges: [(range: NSRange, color: NSColor, type: CustomGlyphType)] = []
        
        textStorage.enumerateAttribute(Self.renderAsBulletKey, in: characterRange, options: []) { value, range, _ in
            guard value != nil else { return }
            let color = textStorage.attribute(.foregroundColor, at: range.location, effectiveRange: nil) as? NSColor ?? NSColor(red: 0.7, green: 0.4, blue: 0.9, alpha: 1.0)
            customRanges.append((range, color, .bullet))
        }
        
        textStorage.enumerateAttribute(Self.todoUncheckedKey, in: characterRange, options: []) { value, range, _ in
            guard value != nil else { return }
            let color = textStorage.attribute(.foregroundColor, at: range.location, effectiveRange: nil) as? NSColor ?? NSColor.gray
            customRanges.append((range, color, .todoUnchecked))
        }
        
        textStorage.enumerateAttribute(Self.todoCheckedKey, in: characterRange, options: []) { value, range, _ in
            guard value != nil else { return }
            let color = textStorage.attribute(.foregroundColor, at: range.location, effectiveRange: nil) as? NSColor ?? NSColor.green
            customRanges.append((range, color, .todoChecked))
        }
        
        if customRanges.isEmpty {
            super.drawGlyphs(forGlyphRange: glyphsToShow, at: origin)
        } else {
            var currentLocation = glyphsToShow.location
            let endLocation = glyphsToShow.location + glyphsToShow.length
            
            for customRange in customRanges.sorted(by: { $0.range.location < $1.range.location }) {
                let glyphRange = self.glyphRange(forCharacterRange: customRange.range, actualCharacterRange: nil)
                
                if currentLocation < glyphRange.location {
                    let beforeRange = NSRange(location: currentLocation, length: glyphRange.location - currentLocation)
                    super.drawGlyphs(forGlyphRange: beforeRange, at: origin)
                }
                
                switch customRange.type {
                case .bullet:
                    drawBullet(forGlyphRange: glyphRange, at: origin, color: customRange.color)
                case .todoUnchecked:
                    drawCheckbox(forGlyphRange: glyphRange, at: origin, checked: false, color: customRange.color)
                case .todoChecked:
                    drawCheckbox(forGlyphRange: glyphRange, at: origin, checked: true, color: customRange.color)
                }
                
                currentLocation = glyphRange.location + glyphRange.length
            }
            
            if currentLocation < endLocation {
                let afterRange = NSRange(location: currentLocation, length: endLocation - currentLocation)
                super.drawGlyphs(forGlyphRange: afterRange, at: origin)
            }
        }
    }
    
    private func drawBullet(forGlyphRange glyphRange: NSRange, at origin: NSPoint, color: NSColor) {
        guard let textContainer = textContainers.first else { return }
        
        // Get the rect for the "- " text
        var boundingRect = self.boundingRect(forGlyphRange: glyphRange, in: textContainer)
        boundingRect.origin.x += origin.x
        boundingRect.origin.y += origin.y
        
        // Get font from text storage
        let characterRange = self.characterRange(forGlyphRange: glyphRange, actualGlyphRange: nil)
        let font = textStorage?.attribute(.font, at: characterRange.location, effectiveRange: nil) as? NSFont ?? NSFont.systemFont(ofSize: 14)
        
        // Draw "• " instead of "- "
        let bulletString = "• "
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: color
        ]
        
        let attrString = NSAttributedString(string: bulletString, attributes: attributes)
        attrString.draw(at: boundingRect.origin)
    }
    
    private func drawCheckbox(forGlyphRange glyphRange: NSRange, at origin: NSPoint, checked: Bool, color: NSColor) {
        guard let textContainer = textContainers.first else { return }
        
        var boundingRect = self.boundingRect(forGlyphRange: glyphRange, in: textContainer)
        boundingRect.origin.x += origin.x
        boundingRect.origin.y += origin.y
        
        // Get the line height from the actual text line for proper sizing
        let characterRange = self.characterRange(forGlyphRange: glyphRange, actualGlyphRange: nil)
        let font = textStorage?.attribute(.font, at: characterRange.location, effectiveRange: nil) as? NSFont ?? NSFont.systemFont(ofSize: 14)
        let lineHeight = boundingRect.height
        let size: CGFloat = min(lineHeight * 0.75, 14)
        let checkboxRect = NSRect(
            x: boundingRect.origin.x + (boundingRect.width - size) / 2,
            y: boundingRect.origin.y + (lineHeight - size) / 2,
            width: size,
            height: size
        )
        
        let path = NSBezierPath(roundedRect: checkboxRect, xRadius: 3, yRadius: 3)
        
        if checked {
            NSColor(red: 0.4, green: 0.8, blue: 0.4, alpha: 1.0).setFill()
            path.fill()
            
            // Draw checkmark
            let checkPath = NSBezierPath()
            let inset: CGFloat = size * 0.25
            let left = checkboxRect.origin.x + inset
            let right = checkboxRect.origin.x + size - inset
            let top = checkboxRect.origin.y + inset
            let bottom = checkboxRect.origin.y + size - inset
            let midX = checkboxRect.origin.x + size * 0.42
            let midY = checkboxRect.origin.y + size - inset
            
            checkPath.move(to: NSPoint(x: left, y: checkboxRect.midY))
            checkPath.line(to: NSPoint(x: midX, y: midY))
            checkPath.line(to: NSPoint(x: right, y: top))
            
            NSColor.white.setStroke()
            checkPath.lineWidth = 1.5
            checkPath.lineCapStyle = .round
            checkPath.lineJoinStyle = .round
            checkPath.stroke()
        } else {
            NSColor.gray.withAlphaComponent(0.4).setStroke()
            path.lineWidth = 1.5
            path.stroke()
        }
    }

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
