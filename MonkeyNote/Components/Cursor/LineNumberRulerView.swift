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

    // Chunked line-start cache: mỗi chunk ≤ ~1024 dòng. Patch 1 edit chỉ chạm
    // đúng 1 chunk + dịch bases các chunk sau (vài chục số) — O(√N) thay vì
    // O(N) dịch cả mảng 40k phần tử bằng loop Swift mỗi keystroke.
    // bases: utf16 offset tuyệt đối của dòng đầu mỗi chunk.
    // lines: starts tương đối trong chunk (phần tử đầu luôn 0).
    private var chunkBases: [Int]?
    private var chunkLines: [[Int]]?
    private let chunkTargetLines = 512
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

        // Ruler làm textStorage delegate để patch cache theo từng edit
        // (ko ai khác dùng delegate này — đã grep).
        textView.textStorage?.delegate = self
        
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
        ensureChunkCache(for: text)
        return lineNumberAt(max(0, min(location, cachedTextLength)))
    }

    /// Line number trên cache đã ensure (draw gọi trực tiếp để khỏi ensure
    /// lại mỗi visible fragment).
    private func lineNumberAt(_ clamped: Int) -> Int {
        guard let bases = chunkBases, let lines = chunkLines, !bases.isEmpty else { return 1 }
        let ci = max(0, Self.upperBound(bases, clamped) - 1)
        let rel = clamped - bases[ci]
        var n = Self.upperBound(lines[ci], rel) // starts <= rel = index 1-based trong chunk
        for i in 0..<ci { n += lines[i].count }
        return max(1, n)
    }

    private func totalLineCount() -> Int {
        guard let lines = chunkLines else { return 1 }
        var n = 0
        for a in lines { n += a.count }
        return max(1, n)
    }
    
    // MARK: - Notifications
    
    @objc private func textDidChange(_ notification: Notification) {
        // Cache do textStorage delegate patch trực tiếp mỗi edit nên ở đây
        // chỉ cần vẽ lại, không full rescan. Trường hợp delegate miss (paste
        // khủng → tự đánh dirty) thì ensureLineStarts tự rebuild khi cần.
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

    /// Single UTF-16 pass chia chunk — cùng convention \n với Coordinator +
    /// ContentViewModel stats. Chạy 1 lần khi mở file/paste lớn, còn gõ thường
    /// thì delegate patch từng chunk (không full rebuild).
    private func ensureChunkCache(for text: String) {
        let utf16Count = text.utf16.count
        if !isCacheDirty, chunkBases != nil, chunkLines != nil, utf16Count == cachedTextLength {
            return
        }
        var bases: [Int] = [0]
        var lines: [[Int]] = [[0]]
        lines[0].reserveCapacity(chunkTargetLines)
        var lineInChunk = 0
        var offset = 0
        for unit in text.utf16 {
            if unit == 0xA {
                lineInChunk += 1
                if lineInChunk >= chunkTargetLines {
                    bases.append(offset + 1)
                    lines.append([0])
                    lineInChunk = 0
                } else {
                    lines[lines.count - 1].append(offset + 1 - bases[bases.count - 1])
                }
            }
            offset += 1
        }
        chunkBases = bases
        chunkLines = lines
        cachedTextLength = utf16Count
        isCacheDirty = false
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
        
        // Cached line starts — built once per file/paste, patched per keystroke.
        ensureChunkCache(for: text)
        let totalLines = totalLineCount()

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
            
            // Binary search trên chunked cache: O(log N) mỗi visible fragment.
            let lineNumber = self.lineNumberAt(max(0, min(charRange.location, self.cachedTextLength)))
            
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

// MARK: - Incremental line-start cache (chỉ xử lý dòng đang sửa)

extension LineNumberRulerView: NSTextStorageDelegate {
    func textStorage(
        _ textStorage: NSTextStorage,
        didProcessEditing editedMask: NSTextStorageEditActions,
        range editedRange: NSRange,
        changeInLength delta: Int
    ) {
        // Đổi attribute (font/màu) không đẻ/mất dòng → bỏ qua.
        guard editedMask.contains(.editedCharacters) else { return }
        // Chưa có cache (mới mở file) → để ensureChunkCache build lazy 1 lần.
        guard var bases = chunkBases, var lines = chunkLines, !isCacheDirty else { return }
        // Paste/replace khủng: đánh dirty, rebuild 1 lần khi cần (hiếm).
        guard editedRange.length <= 4096 else {
            isCacheDirty = true
            return
        }

        let loc = editedRange.location
        let oldReplacedLen = editedRange.length - delta

        // Đếm \n trong đúng vùng vừa sửa (gõ 1 phím = 1 vòng lặp).
        let ns = textStorage.string as NSString
        var newStarts: [Int] = []
        var i = loc
        let end = loc + editedRange.length
        while i < end {
            if ns.character(at: i) == 0xA { newStarts.append(i + 1) }
            i += 1
        }

        // Chunk chứa điểm sửa (bases[0] == 0 nên upperBound >= 1).
        let c = max(0, Self.upperBound(bases, loc) - 1)
        let base = bases[c]
        var arr = lines[c]
        let local = loc - base
        let split = Self.upperBound(arr, local)
        let tail = Self.upperBound(arr, local + oldReplacedLen, from: split)
        arr.replaceSubrange(split..<tail, with: newStarts.map { $0 - base })
        // Đuôi trong chunk chỉ vài trăm phần tử là cùng.
        if delta != 0 {
            for j in (split + newStarts.count)..<arr.count { arr[j] += delta }
        }
        lines[c] = arr
        // Dịch bases các chunk sau (vài chục số).
        if delta != 0 {
            for k in (c + 1)..<bases.count { bases[k] += delta }
        }
        // Chunk phình quá thì chẻ đôi để patch sau vẫn rẻ.
        if arr.count > chunkTargetLines * 2 {
            let mid = arr.count / 2
            let second = arr[mid...].map { $0 - arr[mid] }
            let newBase = base + arr[mid]
            arr.removeSubrange(mid...)
            lines[c] = arr
            lines.insert(second, at: c + 1)
            bases.insert(newBase, at: c + 1)
        }
        chunkBases = bases
        chunkLines = lines
        cachedTextLength += delta
    }
}

private extension LineNumberRulerView {
    /// Index đầu tiên có start > value (binary search, từ `from`).
    static func upperBound(_ starts: [Int], _ value: Int, from: Int = 0) -> Int {
        var lo = from
        var hi = starts.count
        while lo < hi {
            let mid = (lo + hi) >> 1
            if starts[mid] <= value {
                lo = mid + 1
            } else {
                hi = mid
            }
        }
        return lo
    }
}
#endif
