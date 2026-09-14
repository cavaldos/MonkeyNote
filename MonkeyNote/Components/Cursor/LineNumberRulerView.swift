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

    // Cached line-start offsets (UTF-16, matches NSTextView.selectedRange).
    // Rebuilt only on text change — scroll/selection/draw reuse it.
    private var cachedLineStarts: [Int]?
    private var cachedTextLength: Int = -1
    private var isCacheDirty: Bool = true
    private var lastDarkMode: Bool?
    private var lastFontSize: CGFloat = 0
    
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
        // Guard: updateNSView calls this on every SwiftUI update — skip redraw if unchanged.
        if lastDarkMode == isDarkMode { return }
        lastDarkMode = isDarkMode
        lineNumberColor = isDarkMode
            ? NSColor.gray.withAlphaComponent(0.5)
            : NSColor.gray.withAlphaComponent(0.6)
        selectedLineColor = isDarkMode
            ? NSColor.white.withAlphaComponent(0.85)
            : NSColor.black.withAlphaComponent(0.85)
        needsDisplay = true
    }
    
    func updateFont(_ newFont: NSFont) {
        if lastFontSize == newFont.pointSize { return }
        lastFontSize = newFont.pointSize
        // Use monospaced digits for consistent alignment
        font = NSFont.monospacedDigitSystemFont(ofSize: newFont.pointSize * 0.75, weight: .regular)
        needsDisplay = true
    }

    /// Called when text is set programmatically (bypasses NSText.didChangeNotification).
    func invalidateCache() {
        isCacheDirty = true
        needsDisplay = true
    }

    /// Shared helper: O(log N) line number for a UTF-16 location. Used by both
    /// the ruler highlight and Coordinator.textViewDidChangeSelection (StatusBar),
    /// so each keystroke computes the line once instead of twice.
    func lineNumber(forLocation location: Int) -> Int {
        guard let textView = textView else { return 1 }
        let text = textView.string
        if text.isEmpty { return 1 }
        let starts = ensureLineStarts(for: text)
        let clamped = max(0, min(location, cachedTextLength))
        return Self.lineNumber(at: clamped, in: starts)
    }

    static func lineNumber(at location: Int, in lineStarts: [Int]) -> Int {
        // Rightmost start <= location (binary search).
        var lo = 0
        var hi = lineStarts.count - 1
        var result = 1
        while lo <= hi {
            let mid = (lo + hi) >> 1
            if lineStarts[mid] <= location {
                result = mid + 1
                lo = mid + 1
            } else {
                hi = mid - 1
            }
        }
        return result
    }
    
    // MARK: - Notifications
    
    @objc private func textDidChange(_ notification: Notification) {
        isCacheDirty = true
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

    /// Single UTF-16 pass counting \n — same convention as Coordinator +
    /// ContentViewModel stats. O(N) once per edit, reused by every draw/scroll/selection.
    private func ensureLineStarts(for text: String) -> [Int] {
        let utf16Count = text.utf16.count
        if !isCacheDirty, let cached = cachedLineStarts, utf16Count == cachedTextLength {
            return cached
        }
        var starts: [Int] = [0]
        starts.reserveCapacity(max(16, utf16Count / 40))
        var offset = 0
        for unit in text.utf16 {
            if unit == 0xA {
                starts.append(offset + 1)
            }
            offset += 1
        }
        cachedLineStarts = starts
        cachedTextLength = utf16Count
        isCacheDirty = false
        return starts
    }
    
    private func updateCurrentLine() {
        guard let textView = textView else { return }
        if textView.string.isEmpty {
            currentLine = 1
            return
        }
        let cursorPos = textView.selectedRange().location
        currentLine = lineNumber(forLocation: cursorPos)
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
        
        let text = textView.string
        let visibleRect = textView.visibleRect
        let textInset = textView.textContainerInset
        
        // Update current line for selection highlight (O(log N) via cache)
        updateCurrentLine()
        
        // Handle empty document
        if text.isEmpty {
            let yPosition = textInset.height - visibleRect.origin.y + verticalOffset
            drawLineNumber(1, at: yPosition, isCurrentLine: true)
            return
        }
        
        // Cached line starts — built once per edit, reused on scroll/selection.
        let lineStarts = ensureLineStarts(for: text)
        let totalLines = lineStarts.count

        // Fit the gutter to the digit count (converges after one extra draw).
        let digits = String(totalLines).count
        let digitWidth = ("8" as NSString).size(withAttributes: [.font: font]).width
        let fitted = max(Self.emptyWidth, ceil(CGFloat(digits) * digitWidth + rightPadding + 2))
        if abs(fitted - rulerWidth) > 0.5 {
            rulerWidth = fitted
            ruleThickness = fitted
        }
        
        // Viewport-only: never touch layout outside the visible rect.
        // Same pattern as SearchHighlighting.updateVisibleHighlights.
        var visibleGlyphRange = layoutManager.glyphRange(forBoundingRect: visibleRect, in: textContainer)
        if visibleGlyphRange.length == 0 {
            return
        }
        let visibleCharRange = layoutManager.characterRange(forGlyphRange: visibleGlyphRange, actualGlyphRange: nil)
        // Ensure layout only for what we are about to draw.
        layoutManager.ensureLayout(forCharacterRange: visibleCharRange)
        // Re-resolve after layout settled (range is stable, but cheap insurance).
        visibleGlyphRange = layoutManager.glyphRange(forBoundingRect: visibleRect, in: textContainer)
        guard visibleGlyphRange.length > 0 else { return }
        
        // Track which lines we've drawn to avoid duplicates (for wrapped lines)
        var drawnLines = Set<Int>()
        drawnLines.reserveCapacity(64)
        
        // Enumerate only visible fragments (~50) instead of the whole file (~5000).
        layoutManager.enumerateLineFragments(forGlyphRange: visibleGlyphRange) { (lineRect, usedRect, container, glyphRange, stop) in
            // Convert glyph range to character range
            let charRange = layoutManager.characterRange(forGlyphRange: glyphRange, actualGlyphRange: nil)
            
            // Binary search: O(log N) per visible fragment.
            let lineNumber = Self.lineNumber(at: charRange.location, in: lineStarts)
            
            // Skip if we've already drawn this line (handles soft-wrapped lines)
            if drawnLines.contains(lineNumber) {
                return
            }
            drawnLines.insert(lineNumber)
            
            // lineRect.origin.y is in text container coordinates.
            let yInTextView = lineRect.origin.y + textInset.height
            let yInRuler = yInTextView - visibleRect.origin.y + self.verticalOffset
            
            let isCurrentLine = lineNumber == self.currentLine
            self.drawLineNumber(lineNumber, at: yInRuler, isCurrentLine: isCurrentLine)
        }
        
        // Trailing newline: text ending in \n has an empty last line with no fragment.
        // Only pay for its layout when the end of the document is actually visible.
        if text.utf16.last == 0x0A {
            let lastLineNumber = totalLines
            if !drawnLines.contains(lastLineNumber),
               NSMaxRange(visibleCharRange) >= cachedTextLength - 1 {
                let lastGlyphIndex = layoutManager.glyphIndexForCharacter(at: cachedTextLength - 1)
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
