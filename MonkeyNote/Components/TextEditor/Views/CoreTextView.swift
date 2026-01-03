//
//  CoreTextView.swift
//  MonkeyNote
//
//  Custom NSView that renders text using CoreText (CTLineDraw).
//  Implements NSTextInputClient for full keyboard and IME support.
//

#if os(macOS)
import SwiftUI
import AppKit
import CoreText

/// Custom view for rendering text with CoreText
final class CoreTextView: NSView {
    
    // MARK: - Text Storage & Layout
    
    /// Text storage
    let textStorage = CoreTextStorage()
    
    /// Layout engine
    let layoutEngine = TextLayoutEngine()
    
    // MARK: - Selection & Cursor
    
    /// Current selection range (named differently to avoid conflict with NSTextInputClient.selectedRange())
    var selection: TextRange = TextRange(location: 0, length: 0) {
        didSet {
            if selection != oldValue {
                resetCursorBlink()
                needsDisplay = true
                delegate?.coreTextViewSelectionDidChange(self)
            }
        }
    }
    
    /// Current cursor position (when no selection)
    var cursorPosition: Int {
        get { selection.start.offset }
        set { selection = TextRange(location: newValue, length: 0) }
    }
    
    // MARK: - IME Support
    
    /// Marked text for IME composition
    private var markedText: NSMutableAttributedString?
    /// IME marked range (named _markedRange to avoid conflict with NSTextInputClient.markedRange())
    private var _markedRange: NSRange = NSRange(location: NSNotFound, length: 0)
    private var selectedRangeInMarkedText: NSRange = NSRange(location: 0, length: 0)
    
    // MARK: - Cursor Appearance
    
    /// Cursor layer for rendering
    private var cursorLayer: CALayer?
    
    /// Cursor width
    var cursorWidth: CGFloat = 6 {
        didSet { updateCursorAppearance() }
    }
    
    /// Cursor color
    var cursorColor: NSColor = NSColor(red: 222/255, green: 99/255, blue: 74/255, alpha: 1) {
        didSet { updateCursorAppearance() }
    }
    
    /// Cursor blink enabled
    var cursorBlinkEnabled: Bool = true {
        didSet {
            if cursorBlinkEnabled {
                startCursorBlink()
            } else {
                stopCursorBlink()
                cursorLayer?.opacity = 1
            }
        }
    }
    
    /// Cursor animation enabled
    var cursorAnimationEnabled: Bool = true
    
    /// Cursor animation duration
    var cursorAnimationDuration: Double = 0.15
    
    // MARK: - Cursor Blink Timer
    
    private var blinkTimer: Timer?
    private var cursorVisible: Bool = true
    
    // MARK: - Text Appearance
    
    /// Font for text
    var font: NSFont = .monospacedSystemFont(ofSize: 14, weight: .regular) {
        didSet {
            textStorage.defaultAttributes[.font] = font
            layoutEngine.font = font
            textStorage.invalidateCache()
            layoutEngine.invalidateAllLayout()
            needsDisplay = true
        }
    }
    
    /// Text color
    var textColor: NSColor = .textColor {
        didSet {
            textStorage.defaultAttributes[.foregroundColor] = textColor
            textStorage.invalidateCache()
            needsDisplay = true
        }
    }
    
    /// Selection highlight color
    var selectionColor: NSColor = NSColor.selectedTextBackgroundColor
    
    /// Is dark mode
    var isDarkMode: Bool = false {
        didSet {
            textColor = isDarkMode
                ? NSColor.white.withAlphaComponent(0.92)
                : NSColor.black.withAlphaComponent(0.92)
        }
    }
    
    // MARK: - Layout Configuration
    
    /// Text insets
    var textInsets: NSEdgeInsets = NSEdgeInsets(top: 8, left: 8, bottom: 8, right: 8) {
        didSet {
            layoutEngine.config.textInsets = textInsets
            layoutEngine.invalidateAllLayout()
            needsDisplay = true
        }
    }
    
    /// Line spacing
    var lineSpacing: CGFloat = 0 {
        didSet {
            layoutEngine.config.lineSpacing = lineSpacing
            layoutEngine.invalidateAllLayout()
            needsDisplay = true
        }
    }
    
    // MARK: - Delegate
    
    weak var delegate: CoreTextViewDelegate?
    
    // MARK: - Undo Manager
    
    private var _undoManager: UndoManager?
    override var undoManager: UndoManager? {
        if _undoManager == nil {
            _undoManager = UndoManager()
        }
        return _undoManager
    }
    
    // MARK: - Initialization
    
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setup()
    }
    
    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup()
    }
    
    private func setup() {
        wantsLayer = true
        
        // Setup text storage
        textStorage.delegate = layoutEngine
        textStorage.undoManager = undoManager
        textStorage.defaultAttributes = [
            .font: font,
            .foregroundColor: textColor
        ]
        
        // Setup layout engine
        layoutEngine.textStorage = textStorage
        layoutEngine.font = font
        
        // Setup cursor layer
        setupCursorLayer()
        
        // Enable layer-backed view for better performance
        layer?.drawsAsynchronously = true
    }
    
    deinit {
        stopCursorBlink()
    }
    
    // MARK: - View Lifecycle
    
    override var acceptsFirstResponder: Bool { true }
    
    override func becomeFirstResponder() -> Bool {
        let result = super.becomeFirstResponder()
        if result {
            startCursorBlink()
            cursorLayer?.isHidden = false
        }
        return result
    }
    
    override func resignFirstResponder() -> Bool {
        let result = super.resignFirstResponder()
        if result {
            stopCursorBlink()
            cursorLayer?.isHidden = true
        }
        return result
    }
    
    override var isFlipped: Bool { true } // Use top-left origin
    
    // MARK: - Drawing
    
    override func draw(_ dirtyRect: NSRect) {
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        
        // Clear background (transparent)
        context.clear(dirtyRect)
        
        // Perform layout if needed
        if !layoutEngine.isLayoutValid {
            layoutEngine.performFullLayout()
            updateFrameSize()
        }
        
        // Get visible lines
        let visibleLines = layoutEngine.layoutVisibleLines(in: dirtyRect)
        
        // Draw selection background first
        drawSelection(in: context, dirtyRect: dirtyRect)
        
        // Draw text lines
        drawLines(visibleLines, in: context)
        
        // Draw marked text (IME composition)
        if hasMarkedText() {
            drawMarkedText(in: context)
        }
        
        // Update cursor position
        updateCursorPosition()
    }
    
    /// Draw text lines using CTLineDraw
    private func drawLines(_ lines: [TextLine], in context: CGContext) {
        context.saveGState()
        
        // CoreText uses bottom-left origin, but our view is flipped (top-left)
        // So we need to transform coordinates for each line
        
        for line in lines {
            context.saveGState()
            
            // Position for CoreText drawing (need to flip Y for baseline)
            let yPosition = line.origin.y + line.ascent
            context.textPosition = CGPoint(x: line.origin.x, y: yPosition)
            
            // Draw the line
            CTLineDraw(line.ctLine, context)
            
            context.restoreGState()
        }
        
        context.restoreGState()
    }
    
    /// Draw selection highlight
    private func drawSelection(in context: CGContext, dirtyRect: NSRect) {
        guard selection.length > 0 else { return }
        
        let selectionRects = layoutEngine.selectionRects(for: selection)
        
        context.saveGState()
        context.setFillColor(selectionColor.cgColor)
        
        for rect in selectionRects {
            if rect.intersects(dirtyRect) {
                context.fill(rect)
            }
        }
        
        context.restoreGState()
    }
    
    /// Draw marked text (IME composition) with underline
    private func drawMarkedText(in context: CGContext) {
        guard let marked = markedText,
              _markedRange.location != NSNotFound else { return }
        
        // Get position for marked text
        let markedPosition = _markedRange.location
        guard let point = layoutEngine.point(for: TextPosition(offset: markedPosition)) else { return }
        
        // Draw underline for marked text
        let lineIdx = textStorage.lineIndex(for: markedPosition)
        guard let line = layoutEngine.line(at: lineIdx) else { return }
        
        context.saveGState()
        context.setStrokeColor(textColor.cgColor)
        context.setLineWidth(1)
        
        let underlineY = point.y + line.ascent + 2
        let markedWidth = marked.size().width
        
        context.move(to: CGPoint(x: point.x, y: underlineY))
        context.addLine(to: CGPoint(x: point.x + markedWidth, y: underlineY))
        context.strokePath()
        
        context.restoreGState()
    }
    
    // MARK: - Cursor Management
    
    private func setupCursorLayer() {
        let layer = CALayer()
        layer.backgroundColor = cursorColor.cgColor
        layer.cornerRadius = cursorWidth / 2
        
        wantsLayer = true
        self.layer?.addSublayer(layer)
        cursorLayer = layer
    }
    
    private func updateCursorAppearance() {
        cursorLayer?.backgroundColor = cursorColor.cgColor
        cursorLayer?.cornerRadius = cursorWidth / 2
    }
    
    private func updateCursorPosition() {
        guard selection.length == 0 else {
            cursorLayer?.isHidden = true
            return
        }
        
        guard let rect = layoutEngine.cursorRect(for: selection.start, cursorWidth: cursorWidth) else {
            return
        }
        
        cursorLayer?.isHidden = false
        
        if cursorAnimationEnabled {
            CATransaction.begin()
            CATransaction.setAnimationDuration(cursorAnimationDuration)
            CATransaction.setAnimationTimingFunction(CAMediaTimingFunction(name: .easeOut))
            cursorLayer?.frame = rect
            CATransaction.commit()
        } else {
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            cursorLayer?.frame = rect
            CATransaction.commit()
        }
    }
    
    private func startCursorBlink() {
        stopCursorBlink()
        guard cursorBlinkEnabled else { return }
        
        cursorVisible = true
        cursorLayer?.opacity = 1
        
        blinkTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            self.cursorVisible.toggle()
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            self.cursorLayer?.opacity = self.cursorVisible ? 1 : 0
            CATransaction.commit()
        }
    }
    
    private func stopCursorBlink() {
        blinkTimer?.invalidate()
        blinkTimer = nil
    }
    
    private func resetCursorBlink() {
        cursorVisible = true
        cursorLayer?.opacity = 1
        if cursorBlinkEnabled {
            startCursorBlink()
        }
    }
    
    // MARK: - Frame Size
    
    private func updateFrameSize() {
        let newSize = NSSize(
            width: max(bounds.width, layoutEngine.contentWidth),
            height: max(bounds.height, layoutEngine.contentHeight)
        )
        
        if frame.size != newSize {
            setFrameSize(newSize)
        }
    }
    
    // MARK: - Public Interface
    
    /// Get or set the text content
    var string: String {
        get { textStorage.string }
        set {
            textStorage.setString(newValue)
            layoutEngine.invalidateAllLayout()
            cursorPosition = min(cursorPosition, newValue.count)
            needsDisplay = true
        }
    }
    
    /// Insert text at current cursor position
    func insertText(_ string: String) {
        let insertPosition = selection.start.offset
        
        // Delete selected text first if there's a selection
        if selection.length > 0 {
            textStorage.delete(range: selection.nsRange)
        }
        
        // Insert new text
        textStorage.insert(string, at: insertPosition)
        
        // Move cursor
        cursorPosition = insertPosition + string.count
        
        // Update layout
        layoutEngine.invalidateAllLayout()
        needsDisplay = true
        
        // Notify delegate
        delegate?.coreTextViewTextDidChange(self)
    }
    
    /// Delete backward (backspace)
    func deleteBackward() {
        if selection.length > 0 {
            // Delete selection
            textStorage.delete(range: selection.nsRange)
            cursorPosition = selection.start.offset
        } else if cursorPosition > 0 {
            // Delete character before cursor
            let deleteRange = NSRange(location: cursorPosition - 1, length: 1)
            textStorage.delete(range: deleteRange)
            cursorPosition -= 1
        }
        
        layoutEngine.invalidateAllLayout()
        needsDisplay = true
        delegate?.coreTextViewTextDidChange(self)
    }
    
    /// Delete forward (delete key)
    func deleteForward() {
        if selection.length > 0 {
            textStorage.delete(range: selection.nsRange)
            cursorPosition = selection.start.offset
        } else if cursorPosition < textStorage.length {
            let deleteRange = NSRange(location: cursorPosition, length: 1)
            textStorage.delete(range: deleteRange)
        }
        
        layoutEngine.invalidateAllLayout()
        needsDisplay = true
        delegate?.coreTextViewTextDidChange(self)
    }
    
    /// Scroll to make cursor visible
    func scrollToCursor() {
        guard let rect = layoutEngine.cursorRect(for: selection.start, cursorWidth: cursorWidth) else {
            return
        }
        
        // Add some padding around cursor
        let paddedRect = rect.insetBy(dx: -20, dy: -20)
        scrollToVisible(paddedRect)
    }
}

// MARK: - Keyboard Events

extension CoreTextView {
    override func keyDown(with event: NSEvent) {
        // Let input context handle the event for IME support
        interpretKeyEvents([event])
    }
    
    override func insertNewline(_ sender: Any?) {
        insertText("\n")
    }
    
    override func insertTab(_ sender: Any?) {
        insertText("\t")
    }
    
    override func deleteBackward(_ sender: Any?) {
        deleteBackward()
    }
    
    override func deleteForward(_ sender: Any?) {
        deleteForward()
    }
    
    override func moveLeft(_ sender: Any?) {
        if cursorPosition > 0 {
            cursorPosition -= 1
        }
    }
    
    override func moveRight(_ sender: Any?) {
        if cursorPosition < textStorage.length {
            cursorPosition += 1
        }
    }
    
    override func moveUp(_ sender: Any?) {
        let lineIdx = textStorage.lineIndex(for: cursorPosition)
        guard lineIdx > 0 else { return }
        
        // Get current X position
        guard let currentPoint = layoutEngine.point(for: selection.start) else { return }
        
        // Get previous line
        guard let prevLine = layoutEngine.line(at: lineIdx - 1) else { return }
        
        // Find closest position in previous line
        let targetX = currentPoint.x - prevLine.origin.x
        cursorPosition = prevLine.position(forX: targetX)
    }
    
    override func moveDown(_ sender: Any?) {
        let lineIdx = textStorage.lineIndex(for: cursorPosition)
        guard lineIdx < textStorage.lineCount - 1 else { return }
        
        // Get current X position
        guard let currentPoint = layoutEngine.point(for: selection.start) else { return }
        
        // Get next line
        guard let nextLine = layoutEngine.line(at: lineIdx + 1) else { return }
        
        // Find closest position in next line
        let targetX = currentPoint.x - nextLine.origin.x
        cursorPosition = nextLine.position(forX: targetX)
    }
    
    override func moveToBeginningOfLine(_ sender: Any?) {
        let lineRange = textStorage.lineRange(containing: cursorPosition)
        cursorPosition = lineRange.location
    }
    
    override func moveToEndOfLine(_ sender: Any?) {
        let lineRange = textStorage.lineRange(containing: cursorPosition)
        var endPos = lineRange.location + lineRange.length
        // Don't include newline character
        if endPos > 0 && textStorage.character(at: endPos - 1) == "\n" {
            endPos -= 1
        }
        cursorPosition = endPos
    }
    
    override func moveToBeginningOfDocument(_ sender: Any?) {
        cursorPosition = 0
    }
    
    override func moveToEndOfDocument(_ sender: Any?) {
        cursorPosition = textStorage.length
    }
    
    override func selectAll(_ sender: Any?) {
        selection = TextRange(location: 0, length: textStorage.length)
    }
}

// MARK: - Mouse Events

extension CoreTextView {
    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        
        let point = convert(event.locationInWindow, from: nil)
        
        if let position = layoutEngine.textPosition(for: point) {
            if event.clickCount == 2 {
                // Double-click: select word
                selectWord(at: position.offset)
            } else if event.clickCount == 3 {
                // Triple-click: select line
                selectLine(at: position.offset)
            } else {
                // Single click: move cursor
                cursorPosition = position.offset
            }
        }
    }
    
    override func mouseDragged(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        
        if let position = layoutEngine.textPosition(for: point) {
            let start = min(selection.start.offset, cursorPosition)
            let end = position.offset
            selection = TextRange(location: min(start, end), length: abs(end - start))
        }
    }
    
    private func selectWord(at position: Int) {
        let text = textStorage.string as NSString
        let range = text.rangeOfWord(at: position)
        selection = TextRange(range)
    }
    
    private func selectLine(at position: Int) {
        let range = textStorage.lineRange(containing: position)
        selection = TextRange(range)
    }
}

// MARK: - NSTextInputClient

extension CoreTextView: NSTextInputClient {
    
    func insertText(_ string: Any, replacementRange: NSRange) {
        // Clear marked text
        if hasMarkedText() {
            unmarkText()
        }
        
        let text: String
        if let str = string as? String {
            text = str
        } else if let attrStr = string as? NSAttributedString {
            text = attrStr.string
        } else {
            return
        }
        
        // Handle replacement range
        if replacementRange.location != NSNotFound {
            textStorage.replace(range: replacementRange, with: text)
            cursorPosition = replacementRange.location + text.count
        } else {
            insertText(text)
        }
        
        layoutEngine.invalidateAllLayout()
        needsDisplay = true
        delegate?.coreTextViewTextDidChange(self)
    }
    
    func setMarkedText(_ string: Any, selectedRange: NSRange, replacementRange: NSRange) {
        let text: NSAttributedString
        if let str = string as? String {
            text = NSAttributedString(string: str, attributes: textStorage.defaultAttributes)
        } else if let attrStr = string as? NSAttributedString {
            text = attrStr
        } else {
            return
        }
        
        // Store marked text
        markedText = NSMutableAttributedString(attributedString: text)
        selectedRangeInMarkedText = selectedRange
        
        // Calculate marked range in document
        if hasMarkedText() && _markedRange.location != NSNotFound {
            // Replace existing marked text
            textStorage.replace(range: _markedRange, with: text.string)
        } else {
            // Insert new marked text
            let insertPosition = replacementRange.location != NSNotFound
                ? replacementRange.location
                : cursorPosition
            textStorage.insert(text.string, at: insertPosition)
            _markedRange = NSRange(location: insertPosition, length: text.length)
        }
        
        _markedRange = NSRange(location: _markedRange.location, length: text.length)
        
        layoutEngine.invalidateAllLayout()
        needsDisplay = true
    }
    
    func unmarkText() {
        markedText = nil
        _markedRange = NSRange(location: NSNotFound, length: 0)
        selectedRangeInMarkedText = NSRange(location: 0, length: 0)
        needsDisplay = true
    }
    
    func selectedRange() -> NSRange {
        selection.nsRange
    }
    
    func markedRange() -> NSRange {
        _markedRange
    }
    
    func hasMarkedText() -> Bool {
        markedText != nil && _markedRange.location != NSNotFound
    }
    
    func attributedSubstring(forProposedRange range: NSRange, actualRange: NSRangePointer?) -> NSAttributedString? {
        guard range.location != NSNotFound,
              range.location + range.length <= textStorage.length else {
            return nil
        }
        
        actualRange?.pointee = range
        return textStorage.attributedString.attributedSubstring(from: range)
    }
    
    func validAttributesForMarkedText() -> [NSAttributedString.Key] {
        [.font, .foregroundColor, .underlineStyle, .underlineColor]
    }
    
    func firstRect(forCharacterRange range: NSRange, actualRange: NSRangePointer?) -> NSRect {
        actualRange?.pointee = range
        
        guard let point = layoutEngine.point(for: TextPosition(offset: range.location)),
              let line = layoutEngine.line(at: textStorage.lineIndex(for: range.location)) else {
            return .zero
        }
        
        let rect = NSRect(x: point.x, y: point.y, width: 0, height: line.height)
        let windowRect = convert(rect, to: nil)
        return window?.convertToScreen(windowRect) ?? .zero
    }
    
    func characterIndex(for point: NSPoint) -> Int {
        let localPoint = convert(point, from: nil)
        return layoutEngine.textPosition(for: localPoint)?.offset ?? 0
    }
}

// MARK: - Helper Extensions

extension NSString {
    func rangeOfWord(at position: Int) -> NSRange {
        let length = self.length
        guard position >= 0 && position <= length else {
            return NSRange(location: position, length: 0)
        }
        
        var start = position
        var end = position
        
        // Find word boundaries
        while start > 0 {
            let char = self.character(at: start - 1)
            if !CharacterSet.alphanumerics.contains(Unicode.Scalar(char)!) {
                break
            }
            start -= 1
        }
        
        while end < length {
            let char = self.character(at: end)
            if !CharacterSet.alphanumerics.contains(Unicode.Scalar(char)!) {
                break
            }
            end += 1
        }
        
        return NSRange(location: start, length: end - start)
    }
}

// MARK: - Delegate Protocol

protocol CoreTextViewDelegate: AnyObject {
    func coreTextViewTextDidChange(_ view: CoreTextView)
    func coreTextViewSelectionDidChange(_ view: CoreTextView)
}

// MARK: - Default Delegate Implementation

extension CoreTextViewDelegate {
    func coreTextViewTextDidChange(_ view: CoreTextView) {}
    func coreTextViewSelectionDidChange(_ view: CoreTextView) {}
}

#endif
