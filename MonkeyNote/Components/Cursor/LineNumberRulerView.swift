//
//  LineNumberRulerView.swift
//  MonkeyNote
//
//  Created by OpenCode on 04/01/26.
//

#if os(macOS)
import AppKit

class LineNumberRulerView: NSRulerView {
    
    // MARK: - Properties
    
    private weak var textView: NSTextView?
    private var lineNumberColor: NSColor = NSColor.gray
    private var selectedLineColor: NSColor = NSColor.white
    private var font: NSFont = NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .regular)
    
    // Current line tracking
    private var currentLine: Int = 1
    
    // Gutter width tracks the digit count: narrow by default, grows past 99 lines.
    static let emptyWidth: CGFloat = 18
    private var rulerWidth: CGFloat = emptyWidth
    private let rightPadding: CGFloat = 3
    private let verticalOffset: CGFloat = 2
    
    // MARK: - Initialization
    
    init(textView: NSTextView, scrollView: NSScrollView) {
        self.textView = textView
        super.init(scrollView: scrollView, orientation: .verticalRuler)
        
        self.clientView = textView
        self.ruleThickness = rulerWidth
        
        setupNotifications()
    }
    
    required init(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    deinit {
        NotificationCenter.default.removeObserver(self)
    }
    
    // MARK: - Setup
    
    private func setupNotifications() {
        guard let textView = textView else { return }
        
        // Observe text changes
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(textDidChange),
            name: NSText.didChangeNotification,
            object: textView
        )
        
        // Observe selection changes
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(selectionDidChange),
            name: NSTextView.didChangeSelectionNotification,
            object: textView
        )
        
        // Observe scroll changes
        if let clipView = scrollView?.contentView {
            clipView.postsBoundsChangedNotifications = true
            NotificationCenter.default.addObserver(
                self,
                selector: #selector(scrollViewDidScroll),
                name: NSView.boundsDidChangeNotification,
                object: clipView
            )
        }
    }
    
    // MARK: - Configuration
    
    func updateColors(isDarkMode: Bool) {
        lineNumberColor = isDarkMode
            ? NSColor.gray.withAlphaComponent(0.5)
            : NSColor.gray.withAlphaComponent(0.6)
        selectedLineColor = isDarkMode
            ? NSColor.white.withAlphaComponent(0.85)
            : NSColor.black.withAlphaComponent(0.85)
        needsDisplay = true
    }
    
    func updateFont(_ newFont: NSFont) {
        // Use monospaced digits for consistent alignment
        font = NSFont.monospacedDigitSystemFont(ofSize: newFont.pointSize * 0.75, weight: .regular)
        needsDisplay = true
    }
    
    // MARK: - Notifications
    
    @objc private func textDidChange(_ notification: Notification) {
        needsDisplay = true
    }
    
    @objc private func selectionDidChange(_ notification: Notification) {
        updateCurrentLine()
        needsDisplay = true
    }
    
    @objc private func scrollViewDidScroll(_ notification: Notification) {
        needsDisplay = true
    }
    
    // MARK: - Line Calculation
    
    private func updateCurrentLine() {
        guard let textView = textView else { return }
        
        let selectedRange = textView.selectedRange()
        let text = textView.string as NSString
        
        if text.length == 0 {
            currentLine = 1
            return
        }
        
        // Get cursor position and use NSString.lineRange to determine line number
        // This leverages Apple's optimized implementation instead of manual iteration
        let cursorPos = min(selectedRange.location, text.length)
        
        // Use lineRange which internally uses optimized algorithms
        let lineRange = text.lineRange(for: NSRange(location: cursorPos, length: 0))
        
        // Count lines by iterating through line ranges (much faster than character-by-character)
        var lineNumber = 1
        var searchPos = 0
        while searchPos < lineRange.location {
            let currentLineRange = text.lineRange(for: NSRange(location: searchPos, length: 0))
            lineNumber += 1
            searchPos = NSMaxRange(currentLineRange)
            if searchPos == currentLineRange.location { break } // Safety check
        }
        currentLine = lineNumber
    }
    
    // MARK: - Drawing
    
    override func draw(_ dirtyRect: NSRect) {
        // Erase first: a clear fill with sourceOver is a no-op and leaves
        // ghost numbers behind whenever edits shift lines up/down.
        NSColor.clear.set()
        dirtyRect.fill(using: .copy)

        drawLineNumbers(in: dirtyRect)
    }
    
    private func drawLineNumbers(in rect: NSRect) {
        guard let textView = textView,
              let layoutManager = textView.layoutManager,
              let textContainer = textView.textContainer else { return }
        
        let text = textView.string as NSString
        let visibleRect = textView.visibleRect
        let textInset = textView.textContainerInset
        
        // Update current line for selection highlight
        updateCurrentLine()
        
        // Handle empty document
        if text.length == 0 {
            let yPosition = textInset.height - visibleRect.origin.y + verticalOffset
            drawLineNumber(1, at: yPosition, isCurrentLine: true)
            return
        }
        
        // Ensure layout is complete
        layoutManager.ensureLayout(for: textContainer)
        
        // Build a map of character index -> line number
        var lineStarts: [Int] = [0] // Line 1 starts at character 0
        var searchIndex = 0
        while searchIndex < text.length {
            let lineRange = text.lineRange(for: NSRange(location: searchIndex, length: 0))
            let nextLineStart = NSMaxRange(lineRange)
            if nextLineStart > searchIndex && nextLineStart <= text.length {
                lineStarts.append(nextLineStart)
            }
            searchIndex = nextLineStart
            if searchIndex == lineRange.location { break }
        }

        // Fit the gutter to the digit count (converges after one extra draw).
        let digits = String(lineStarts.count).count
        let digitWidth = ("8" as NSString).size(withAttributes: [.font: font]).width
        let fitted = max(Self.emptyWidth, ceil(CGFloat(digits) * digitWidth + rightPadding + 2))
        if abs(fitted - rulerWidth) > 0.5 {
            rulerWidth = fitted
            ruleThickness = fitted
        }
        
        // Get the full glyph range
        let fullGlyphRange = layoutManager.glyphRange(for: textContainer)
        guard fullGlyphRange.length > 0 else { return }
        
        // Track which lines we've drawn to avoid duplicates (for wrapped lines)
        var drawnLines = Set<Int>()
        
        // Use enumerateLineFragments to iterate through all line fragments
        layoutManager.enumerateLineFragments(forGlyphRange: fullGlyphRange) { (lineRect, usedRect, container, glyphRange, stop) in
            // Convert glyph range to character range
            let charRange = layoutManager.characterRange(forGlyphRange: glyphRange, actualGlyphRange: nil)
            
            // Find the line number for this character position
            var lineNumber = 1
            for (index, startPos) in lineStarts.enumerated() {
                if charRange.location >= startPos {
                    lineNumber = index + 1
                } else {
                    break
                }
            }
            
            // Skip if we've already drawn this line (handles soft-wrapped lines)
            if drawnLines.contains(lineNumber) {
                return
            }
            
            // Calculate Y position in ruler coordinates
            // lineRect.origin.y is in text container coordinates
            // Add textInset to get text view coordinates
            // Subtract visibleRect.origin.y to get visible/ruler coordinates
            let yInTextView = lineRect.origin.y + textInset.height
            let yInRuler = yInTextView - visibleRect.origin.y + self.verticalOffset
            
            // Only draw if visible (with some padding)
            let rulerHeight = self.bounds.height
            if yInRuler >= -30 && yInRuler <= rulerHeight + 30 {
                drawnLines.insert(lineNumber)
                let isCurrentLine = lineNumber == self.currentLine
                self.drawLineNumber(lineNumber, at: yInRuler, isCurrentLine: isCurrentLine)
            }
        }
        
        // Handle trailing newline - if text ends with \n, add one more line number
        if text.length > 0 && text.character(at: text.length - 1) == UInt16(0x0A) { // 0x0A is newline
            // The last line number is lineStarts.count (not +1)
            // because lineStarts already contains the start position of the empty last line
            let lastLineNumber = lineStarts.count
            if !drawnLines.contains(lastLineNumber) {
                // Get the rect after the last character
                let lastGlyphIndex = layoutManager.glyphIndexForCharacter(at: text.length - 1)
                let lastLineRect = layoutManager.lineFragmentRect(forGlyphAt: lastGlyphIndex, effectiveRange: nil)
                let yInTextView = lastLineRect.origin.y + lastLineRect.height + textInset.height
                let yInRuler = yInTextView - visibleRect.origin.y + verticalOffset
                
                let rulerHeight = self.bounds.height
                if yInRuler >= -30 && yInRuler <= rulerHeight + 30 {
                    let isCurrentLine = lastLineNumber == self.currentLine
                    self.drawLineNumber(lastLineNumber, at: yInRuler, isCurrentLine: isCurrentLine)
                }
            }
        }
    }
    
    private func drawLineNumber(_ number: Int, at y: CGFloat, isCurrentLine: Bool) {
        let lineNumberString = "\(number)"
        
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: isCurrentLine ? selectedLineColor : lineNumberColor
        ]
        
        let attributedString = NSAttributedString(string: lineNumberString, attributes: attributes)
        let stringSize = attributedString.size()
        
        // Right-align the number
        let x = rulerWidth - stringSize.width - rightPadding
        let drawY = y + (font.ascender - font.descender - stringSize.height) / 2 + 2
        
        attributedString.draw(at: NSPoint(x: x, y: drawY))
    }
    
    override var isFlipped: Bool {
        return true
    }
}
#endif
