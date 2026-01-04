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
    
    // Fixed width for ruler
    private let rulerWidth: CGFloat = 24
    private let rightPadding: CGFloat = 4
    
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
        
        // Count newlines before cursor position
        // Line number = number of newline characters before cursor + 1
        let cursorPos = min(selectedRange.location, text.length)
        var newlineCount = 0
        for i in 0..<cursorPos {
            if text.character(at: i) == UInt16(0x0A) { // 0x0A is newline '\n'
                newlineCount += 1
            }
        }
        currentLine = newlineCount + 1
    }
    
    // MARK: - Drawing
    
    override func draw(_ dirtyRect: NSRect) {
        // Draw background (transparent)
        NSColor.clear.setFill()
        dirtyRect.fill()
        
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
            let yPosition = textInset.height - visibleRect.origin.y
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
            let yInRuler = yInTextView - visibleRect.origin.y
            
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
                let yInRuler = yInTextView - visibleRect.origin.y
                
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
