//
//  CursorTextEditor.swift
//  MonkeyNote
//
//  Created by Nguyen Ngoc Khanh on 24/12/25.
//
//  Core class containing all properties. Methods are separated into extensions in features/ folder.
//

#if os(macOS)
import SwiftUI
import AppKit

class CursorTextView: NSTextView {
    // MARK: - Cursor Properties
    var cursorWidth: CGFloat = 6
    var cursorBlinkEnabled: Bool = true {
        didSet {
            if cursorBlinkEnabled != oldValue {
                if cursorBlinkEnabled {
                    startBlinkTimer()
                } else {
                    stopBlinkTimer()
                    cursorLayer?.removeAnimation(forKey: "caretBlink")
                    cursorLayer?.opacity = 1
                }
            }
        }
    }
    var cursorAnimationEnabled: Bool = true
    var cursorAnimationDuration: Double = 0.15
    
    // MARK: - Search Properties
    var searchText: String = ""
    var currentSearchIndex: Int = 0
    var onSearchMatchesChanged: ((Int, Bool) -> Void)?  // (count, isComplete)
    var searchMatchRanges: [NSRange] = []  // All matches for navigation
    
    // Search optimization - viewport-based highlighting
    var allMatchRanges: [NSRange] = []  // Full list from background search
    var visibleHighlightedRanges: Set<Int> = []  // Indices of currently highlighted matches
    var searchTask: Task<Void, Never>?  // Background search task
    var isSearchComplete: Bool = false
    var lastSearchQuery: String = ""
    var lastVisibleRect: NSRect = .zero
    
    // Layer pooling for reuse
    var layerPool: [CALayer] = []
    
    // MARK: - Autocomplete Properties
    var autocompleteEnabled: Bool = true
    var autocompleteDelay: Double = 0.0
    var autocompleteOpacity: Double = 0.5
    var suggestionMode: String = "word"  // "word" or "sentence"
    
    // Autocomplete ghost text
    var ghostTextLayer: CATextLayer?
    var currentSuggestion: String?
    var suggestionWordStart: Int = 0
    var suggestionTask: Task<Void, Never>?
    
    // MARK: - Double-tap Navigation Properties
    var doubleTapNavigationEnabled: Bool = true
    var doubleTapDelay: Double = 300  // milliseconds
    var lastKeyCode: UInt16 = 0
    var lastKeyTime: Date = Date.distantPast
    
    // MARK: - Scroll Properties
    var disableAutoScroll: Bool = false
    var isScrolling: Bool = false
    
    // MARK: - Layer Properties
    var cursorLayer: CALayer?
    var lastCursorRect: NSRect = .zero
    var highlightLayers: [CALayer] = []
    var currentMatchLayers: [CALayer] = []  // Track current match layers for shake animation
    
    // MARK: - Cursor Blink Properties
    var blinkTimer: Timer?
    var cursorVisible: Bool = true
    
    // MARK: - Slash Command Properties
    var slashCommandController = SlashCommandWindowController()
    var slashCommandRange: NSRange?
    var slashFilterText: String = ""  // Track text typed after "/"
    
    // MARK: - Dictionary Lookup Properties
    var dictionaryLookupController: DictionaryLookupWindowController?
    var dictionaryLookupRange: NSRange?  // Range of "word\" including the backslash
    var dictionaryLanguage: String = "en"
    
    // MARK: - Auto Pair Properties
    var autoPairEnabled: Bool = true
    let autoPairMap: [String: String] = [
        "\"": "\"",
        "'": "'",
        "(": ")",
        "[": "]",
        "{": "}",
        "`": "`"
    ]
    let closingChars: Set<String> = ["\"", "'", ")", "]", "}", "`"]
    
    // MARK: - Selection Toolbar Properties
    var selectionToolbarController = SelectionToolbarController.shared
    
    // Flag to track if selection is from search navigation
    var isNavigatingSearch: Bool = false
    
    // MARK: - Lifecycle
    
    deinit {
        stopBlinkTimer()
    }
    
    // MARK: - Override Methods
    
    override func becomeFirstResponder() -> Bool {
        let result = super.becomeFirstResponder()
        if result && cursorBlinkEnabled {
            startBlinkTimer()
        }
        return result
    }

    override func drawInsertionPoint(in rect: NSRect, color: NSColor, turnedOn flag: Bool) {
        // We handle blinking ourselves with the timer, so ignore the flag parameter
        var thickRect = rect
        thickRect.size.width = cursorWidth

        if cursorLayer == nil {
            let layer = CALayer()
            layer.cornerRadius = cursorWidth / 2
            layer.backgroundColor = color.cgColor
            layer.anchorPoint = CGPoint(x: 0.5, y: 0.5)
            // Chặn implicit animation — position do animateCaretLayer điều khiển explicit,
            // còn lại set cứng (skill: chỉ animate transform/opacity).
            layer.actions = [
                "position": NSNull(),
                "bounds": NSNull(),
                "backgroundColor": NSNull(),
                "cornerRadius": NSNull(),
                "opacity": NSNull()
            ]
            wantsLayer = true
            self.layer?.addSublayer(layer)
            cursorLayer = layer

            // Start blink timer when cursor layer is created
            if cursorBlinkEnabled {
                startBlinkTimer()
            }
        }

        // Chỉ set màu/góc khi đổi — tránh implicit animation lẫn vào lúc slide
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        if cursorLayer?.backgroundColor != color.cgColor {
            cursorLayer?.backgroundColor = color.cgColor
        }
        let radius = cursorWidth / 2
        if cursorLayer?.cornerRadius != radius {
            cursorLayer?.cornerRadius = radius
        }
        CATransaction.commit()

        if lastCursorRect != thickRect {
            animateCaretLayer(to: thickRect)
            lastCursorRect = thickRect
            // Reset blink when cursor moves
            resetBlinkTimer()
        }
    }

    override func setNeedsDisplay(_ invalidRect: NSRect, avoidAdditionalLayout flag: Bool) {
        var extendedRect = invalidRect
        extendedRect.size.width += cursorWidth
        super.setNeedsDisplay(extendedRect, avoidAdditionalLayout: flag)
    }

    override func resignFirstResponder() -> Bool {
        let didResign = super.resignFirstResponder()
        if didResign {
            stopBlinkTimer()
            cursorLayer?.removeAnimation(forKey: "caretBlink")
            cursorLayer?.removeAnimation(forKey: "caretSlide")
            cursorLayer?.opacity = 0
        }
        return didResign
    }

    override var rangeForUserCompletion: NSRange {
        selectedRange()
    }
    
    override func keyDown(with event: NSEvent) {
        // Handle slash command menu navigation
        if slashCommandController.isVisible {
            if handleSlashCommandKeyDown(with: event) {
                return
            }
        }
        
        // Handle dictionary lookup - dismiss on any key except viewing
        if let dictController = dictionaryLookupController, dictController.isVisible {
            if handleDictionaryLookupKeyDown(with: event) {
                return
            }
        }
        
        // Handle Escape to dismiss autocomplete suggestion
        if event.keyCode == 53 { // Escape
            if currentSuggestion != nil {
                hideSuggestion()
                return
            }
        }
        
        // Handle formatting shortcuts (Cmd+B, Cmd+I, Cmd+E)
        if event.modifierFlags.contains(.command) {
            if handleFormattingShortcut(with: event) {
                return
            }
        }
        
        guard !event.isARepeat else {
            super.keyDown(with: event)
            return
        }
        
        // Handle double-tap navigation (Delete, Left Arrow, Right Arrow)
        if handleDoubleTapNavigation(with: event) {
            return
        }
        
        // Handle Tab key - check for autocomplete suggestion first
        if event.keyCode == 48 {
            if handleTabKey(with: event) {
                return
            }
        }
        
        // Handle Shift + Enter - soft line break (continue same list item)
        if event.keyCode == 36 && event.modifierFlags.contains(.shift) {
            if handleShiftEnter() {
                return
            }
        }
        
        // Handle Enter for list continuation
        if event.keyCode == 36 {
            if handleEnterKey() {
                return
            }
        }
        
        super.keyDown(with: event)
    }
    
    override func insertText(_ insertString: Any, replacementRange: NSRange) {
        guard let str = insertString as? String else {
            super.insertText(insertString, replacementRange: replacementRange)
            return
        }
        
        // If slash command menu is visible, update filter with typed character
        if slashCommandController.isVisible {
            if handleSlashCommandInsertText(str, replacementRange: replacementRange) {
                return
            }
        }
        
        // Check for space after "." or "-" at line start to convert to bullet
        if handleBulletConversion(str) {
            return
        }
        
        // MARK: - Auto Pair Brackets/Quotes
        if handleAutoPair(str, replacementRange: replacementRange) {
            return
        }
        
        super.insertText(insertString, replacementRange: replacementRange)
        
        // Update autocomplete suggestion
        // Hide suggestion if space or punctuation is typed
        if str.rangeOfCharacter(from: CharacterSet.alphanumerics) == nil {
            hideSuggestion()
        } else {
            updateSuggestion()
        }
        
        // Check if "\" was typed - show dictionary lookup for word before it
        if str == "\\" {
            showDictionaryLookupForWordBeforeBackslash()
            return
        }
        
        // Check if "/" was typed at the beginning of a line
        handleSlashAtLineStart(str)
    }
    
    override func deleteBackward(_ sender: Any?) {
        super.deleteBackward(sender)
        
        // Update suggestion after deletion
        updateSuggestion()
    }
    
    override func setSelectedRange(_ charRange: NSRange) {
        super.setSelectedRange(charRange)
        handleSelectionChange()
    }
    
    override func setSelectedRange(_ charRange: NSRange, affinity: NSSelectionAffinity, stillSelecting stillSelectingFlag: Bool) {
        super.setSelectedRange(charRange, affinity: affinity, stillSelecting: stillSelectingFlag)
        if !stillSelectingFlag {
            handleSelectionChange()
        }
    }
    
    // MARK: - Link Handling
    
    override func clicked(onLink link: Any, at charIndex: Int) {
        // Handle link click manually to prevent errors
        guard let urlString = link as? String else { return }
        
        // Try to create URL and open it
        var urlToOpen: URL?
        
        if let url = URL(string: urlString) {
            // Check if URL has a scheme
            if url.scheme != nil {
                urlToOpen = url
            } else {
                // Add https:// if no scheme
                urlToOpen = URL(string: "https://\(urlString)")
            }
        }
        
        if let url = urlToOpen {
            NSWorkspace.shared.open(url)
        }
    }
    
    // Prevent default link behavior that causes errors
    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        let charIndex = characterIndexForInsertion(at: point)
        
        // Check if clicked on a todo checkbox
        if charIndex < textStorage?.length ?? 0,
           let attrs = textStorage?.attributes(at: charIndex, effectiveRange: nil) {
            if attrs[NSAttributedString.Key("todoUnchecked")] != nil || attrs[NSAttributedString.Key("todoChecked")] != nil {
                toggleTodoAtCharIndex(charIndex)
                return
            }
        }
        
        // Check if clicked on a link
        if charIndex < textStorage?.length ?? 0,
           let attrs = textStorage?.attributes(at: charIndex, effectiveRange: nil),
           let link = attrs[.link] {
            clicked(onLink: link, at: charIndex)
            return
        }
        
        super.mouseDown(with: event)
    }
    
    // MARK: - Todo Toggle
    
    func toggleTodoAtCharIndex(_ charIndex: Int) {
        let text = self.string as NSString
        let lineRange = text.lineRange(for: NSRange(location: charIndex, length: 0))
        let lineText = text.substring(with: lineRange)
        
        let newLineText: String
        if lineText.hasPrefix("- [ ] ") {
            newLineText = "- [x] " + String(lineText.dropFirst("- [ ] ".count))
        } else if lineText.hasPrefix("- [x] ") || lineText.hasPrefix("- [X] ") {
            newLineText = "- [ ] " + String(lineText.dropFirst("- [x] ".count))
        } else if lineText.hasPrefix("- [ ]") {
            newLineText = "- [x]" + String(lineText.dropFirst("- [ ]".count))
        } else if lineText.hasPrefix("- [x]") || lineText.hasPrefix("- [X]") {
            newLineText = "- [ ]" + String(lineText.dropFirst("- [x]".count))
        } else {
            return
        }
        
        let savedSelection = self.selectedRange()
        self.replaceCharacters(in: lineRange, with: newLineText)
        self.setSelectedRange(savedSelection)
    }
    
    override func layout() {
        super.layout()

        // Only update search highlights if search is active
        guard !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        
        // Debounce scroll updates to prevent excessive redraws
        NSObject.cancelPreviousPerformRequests(withTarget: self, selector: #selector(debouncedUpdateHighlights), object: nil)
        perform(#selector(debouncedUpdateHighlights), with: nil, afterDelay: 0.08)
    }

    override func didChangeText() {
        super.didChangeText()
        // Document edited (type/delete/paste/undo) while search is active:
        // cached NSRanges are stale -> force re-search on next updateHighlights().
        if !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            isSearchComplete = false
        }
    }
    
    @objc func debouncedUpdateHighlights() {
        updateHighlights()
    }
    
    // Override to prevent flickering when scrolling to cursor
    override func scrollRangeToVisible(_ range: NSRange) {
        // Prevent multiple rapid scroll calls that cause flickering
        guard !isScrolling else { return }
        
        isScrolling = true
        super.scrollRangeToVisible(range)
        
        // Reset flag after a short delay to batch scroll requests
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
            self?.isScrolling = false
        }
    }
}

// MARK: - ThickCursorTextEditor (NSViewRepresentable)

// Scroller không vẽ nền slot, knob vẽ tay mỏng mờ.
final class ClearTrackScroller: NSScroller {
    override func drawKnobSlot(in slotRect: NSRect, highlight flag: Bool) {}
    override func drawKnob() {
        let slot = rect(for: .knob)
        guard !slot.isEmpty, slot.width > 0, slot.height > 0 else { return }
        let w: CGFloat = 5
        let r = NSRect(x: slot.midX - w / 2, y: slot.minY + 1,
                       width: w, height: max(slot.height - 2, w))
        let dark = effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        let c = dark ? NSColor.white.withAlphaComponent(0.3)
                     : NSColor.black.withAlphaComponent(0.25)
        c.setFill()
        NSBezierPath(roundedRect: r, xRadius: w / 2, yRadius: w / 2).fill()
    }
}

struct ThickCursorTextEditor: NSViewRepresentable {
    @Binding var text: String
    var isDarkMode: Bool
    var cursorWidth: CGFloat
    var cursorBlinkEnabled: Bool
    var cursorAnimationEnabled: Bool
    var cursorAnimationDuration: Double
    var fontSize: Double
    var fontFamily: String
    var searchText: String
    var autocompleteEnabled: Bool
    var autocompleteDelay: Double
    var autocompleteOpacity: Double
    var suggestionMode: String
    var horizontalPadding: CGFloat = 0

    // Line numbers
    var showLineNumbers: Bool = true
    
    // Double-tap navigation
    var doubleTapNavigationEnabled: Bool = true
    var doubleTapDelay: Double = 300
    
    // Search navigation
    var currentSearchIndex: Int = 0
    var onSearchMatchesChanged: ((Int, Bool) -> Void)? = nil  // Reports (count, isComplete)
    var onNavigateToMatch: ((Int) -> Void)? = nil  // Called when should navigate to specific match

    // Cursor position callback
    var onCursorLineChanged: ((Int) -> Void)? = nil


    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.scrollerStyle = .overlay
        scrollView.autohidesScrollers = true
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.borderType = .noBorder
        scrollView.backgroundColor = .clear
        scrollView.drawsBackground = false
        scrollView.contentView.drawsBackground = false
        scrollView.contentView.backgroundColor = .clear
        let vScroller = ClearTrackScroller()
        vScroller.scrollerStyle = .overlay
        scrollView.verticalScroller = vScroller

        let layoutManager = CursorLayoutManager()
        layoutManager.cursorWidth = cursorWidth

        // Plain text storage — no markdown rendering (removed for large-file performance)
        let textStorage = NSTextStorage()
        textStorage.addLayoutManager(layoutManager)

        let textContainer = NSTextContainer()
        textContainer.widthTracksTextView = true
        textContainer.containerSize = NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude)
        layoutManager.addTextContainer(textContainer)

        let textView = CursorTextView(frame: .zero, textContainer: textContainer)
        textView.cursorWidth = cursorWidth
        textView.cursorBlinkEnabled = cursorBlinkEnabled
        textView.cursorAnimationEnabled = cursorAnimationEnabled
        textView.cursorAnimationDuration = cursorAnimationDuration
        textView.searchText = searchText
        textView.currentSearchIndex = currentSearchIndex
        textView.onSearchMatchesChanged = onSearchMatchesChanged
        textView.autocompleteEnabled = autocompleteEnabled
        textView.autocompleteDelay = autocompleteDelay
        textView.autocompleteOpacity = autocompleteOpacity
        textView.suggestionMode = suggestionMode
        textView.doubleTapNavigationEnabled = doubleTapNavigationEnabled
        textView.doubleTapDelay = doubleTapDelay
        textView.isRichText = false  // Plain text — no markdown rendering
        textView.allowsUndo = true
        textView.isEditable = true
        textView.isSelectable = true
        textView.backgroundColor = .clear
        textView.drawsBackground = false
        textView.textContainerInset = NSSize(width: horizontalPadding, height: 0)
        textView.textContainer?.lineFragmentPadding = 0 // số dòng sát chữ (mặc định 5pt)
        
        // Disable automatic text substitution features
        textView.isAutomaticQuoteSubstitutionEnabled = false // disable "smart quotes"
        textView.isAutomaticDashSubstitutionEnabled = false // disable — em dash substitution
        textView.isAutomaticTextReplacementEnabled = false // disable text replacement (e.g., (c) -> ©)
        textView.isAutomaticSpellingCorrectionEnabled = false // underline only, never auto-replace
        textView.smartInsertDeleteEnabled = false // disable smart insert/delete
        textView.applySpellcheckSettings() // underline misspelled words (language shared with autocomplete)

        
        // Critical settings for proper scrolling
        textView.minSize = NSSize(width: 0, height: 0)
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]

        let font: NSFont
        switch fontFamily {
        case "rounded":
            font = NSFont.systemFont(ofSize: fontSize, weight: .regular)
        case "serif":
            font = NSFont(name: "Times New Roman", size: fontSize) ?? NSFont.systemFont(ofSize: fontSize, weight: .regular)
        default:
            if let customFont = NSFont(name: fontFamily, size: fontSize) {
                font = customFont
            } else {
                font = NSFont.monospacedSystemFont(ofSize: fontSize, weight: .regular)
            }
        }
        textView.font = font
        applyParagraphSpacing(textView, fontSize: fontSize)

        textView.textColor = isDarkMode
            ? NSColor.white.withAlphaComponent(0.92)
            : NSColor.black.withAlphaComponent(0.92)
        textView.insertionPointColor = NSColor(
            red: 222.0 / 255.0,
            green: 99.0 / 255.0,
            blue: 74.0 / 255.0,
            alpha: 1.0
        )

        textView.delegate = context.coordinator
        textView.string = text

        // Setup line number ruler view
        if showLineNumbers {
            scrollView.hasVerticalRuler = true
            scrollView.rulersVisible = true
            let rulerView = LineNumberRulerView(textView: textView, scrollView: scrollView)
            rulerView.updateColors(isDarkMode: isDarkMode)
            rulerView.updateFont(font)
            scrollView.verticalRulerView = rulerView
            context.coordinator.rulerView = rulerView
        }

        scrollView.documentView = textView
        context.coordinator.textView = textView

        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? CursorTextView else { return }

        if textView.string != text {
            let selectedRange = textView.selectedRange()
            textView.string = text
            let safeLocation = min(selectedRange.location, text.utf16.count)
            let safeLength = min(selectedRange.length, text.utf16.count - safeLocation)
            textView.setSelectedRange(NSRange(location: safeLocation, length: safeLength))
            // Nội dung đổi ngầm (replace/đổi note/undo ngoài) -> ranges cũ sai lệch
            textView.isSearchComplete = false
            // set string xóa attributes -> phủ lại spacing 1 lần
            if let ts = textView.textStorage, ts.length > 0 {
                ts.addAttribute(.paragraphStyle, value: paragraphStyle(fontSize: fontSize), range: NSRange(location: 0, length: ts.length))
            }
        }

        textView.cursorWidth = cursorWidth
        textView.cursorBlinkEnabled = cursorBlinkEnabled
        textView.cursorAnimationEnabled = cursorAnimationEnabled
        textView.cursorAnimationDuration = cursorAnimationDuration
        textView.searchText = searchText
        textView.currentSearchIndex = currentSearchIndex
        textView.onSearchMatchesChanged = onSearchMatchesChanged
        textView.autocompleteEnabled = autocompleteEnabled
        textView.autocompleteDelay = autocompleteDelay
        textView.autocompleteOpacity = autocompleteOpacity
        textView.suggestionMode = suggestionMode
        textView.doubleTapNavigationEnabled = doubleTapNavigationEnabled
        textView.doubleTapDelay = doubleTapDelay
        textView.applySpellcheckSettings()
        if let layoutManager = textView.layoutManager as? CursorLayoutManager {
            layoutManager.cursorWidth = cursorWidth
        }

        let font: NSFont
        switch fontFamily {
        case "rounded":
            font = NSFont.systemFont(ofSize: fontSize, weight: .regular)
        case "serif":
            font = NSFont(name: "Times New Roman", size: fontSize) ?? NSFont.systemFont(ofSize: fontSize, weight: .regular)
        default:
            if let customFont = NSFont(name: fontFamily, size: fontSize) {
                font = customFont
            } else {
                font = NSFont.monospacedSystemFont(ofSize: fontSize, weight: .regular)
            }
        }
        if textView.font?.pointSize != font.pointSize || textView.font?.fontName != font.fontName {
            textView.font = font
        }
        // Giữ spacing khi đổi font + đảm bảo dòng mới gõ tiếp vẫn thưa
        applyParagraphSpacing(textView, fontSize: fontSize)
        
        let textColor = isDarkMode
            ? NSColor.white.withAlphaComponent(0.92)
            : NSColor.black.withAlphaComponent(0.92)

        if textView.textColor != textColor {
            textView.textColor = textColor
        }

        // Update line number ruler view
        updateRulerView(scrollView: scrollView, context: context, font: font)
        
        // Check if search index changed and navigate to match
        let previousIndex = context.coordinator.lastSearchIndex
        let trimmedSearch = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedSearch.isEmpty {
            if currentSearchIndex != previousIndex {
                context.coordinator.lastSearchIndex = currentSearchIndex
                // Need to update highlights first to populate searchMatchRanges
                textView.updateHighlights()
                // Then navigate to the match
                textView.navigateToMatch(index: currentSearchIndex)
            } else {
                textView.updateHighlights()
            }
        } else if !textView.lastSearchQuery.isEmpty || !textView.highlightLayers.isEmpty {
            // Clear stale search layers once when search is closed
            textView.updateHighlights()
        }
    }

    private func updateRulerView(scrollView: NSScrollView, context: Context, font: NSFont) {
        if showLineNumbers {
            if let rulerView = context.coordinator.rulerView {
                rulerView.updateColors(isDarkMode: isDarkMode)
                rulerView.updateFont(font)
                rulerView.needsDisplay = true
            } else {
                guard let textView = scrollView.documentView as? CursorTextView else { return }
                let rulerView = LineNumberRulerView(textView: textView, scrollView: scrollView)
                rulerView.updateColors(isDarkMode: isDarkMode)
                rulerView.updateFont(font)
                scrollView.verticalRulerView = rulerView
                scrollView.hasVerticalRuler = true
                scrollView.rulersVisible = true
                context.coordinator.rulerView = rulerView
            }
        } else {
            scrollView.rulersVisible = false
            scrollView.hasVerticalRuler = false
        }
    }

    // Enter = paragraph mới -> paragraphSpacing; wrap dài tự tràn giữ nguyên (lineSpacing = 0)
    private func paragraphStyle(fontSize: Double) -> NSParagraphStyle {
        let style = NSMutableParagraphStyle()
        style.paragraphSpacing = round(fontSize * 0.35)
        style.lineSpacing = 0
        return style
    }

    private func applyParagraphSpacing(_ textView: CursorTextView, fontSize: Double) {
        let style = paragraphStyle(fontSize: fontSize)
        // Cheap check: chỉ phủ lại storage khi spacing đổi (tránh full-scan mỗi keystroke)
        let current = textView.defaultParagraphStyle
        textView.defaultParagraphStyle = style
        var attrs = textView.typingAttributes
        attrs[.paragraphStyle] = style
        textView.typingAttributes = attrs
        if current?.paragraphSpacing != style.paragraphSpacing || current?.lineSpacing != style.lineSpacing,
           let ts = textView.textStorage, ts.length > 0 {
            ts.addAttribute(.paragraphStyle, value: style, range: NSRange(location: 0, length: ts.length))
        }
    }

    class Coordinator: NSObject, NSTextViewDelegate {
        var parent: ThickCursorTextEditor
        fileprivate weak var textView: CursorTextView?
        var lastSearchIndex: Int = 0
        var rulerView: LineNumberRulerView?

        init(_ parent: ThickCursorTextEditor) {
            self.parent = parent
            super.init()
            
            // Listen for focusEditor notification
            NotificationCenter.default.addObserver(
                self,
                selector: #selector(focusEditor),
                name: Notification.Name("focusEditor"),
                object: nil
            )
        }
        
        deinit {
            NotificationCenter.default.removeObserver(self)
        }
        
        @objc func focusEditor() {
            DispatchQueue.main.async {
                self.textView?.window?.makeFirstResponder(self.textView)
            }
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            parent.text = textView.string
        }
        
        func textViewDidChangeSelection(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            
            // Calculate and report cursor line with a single allocation-free
            // pass over UTF-16 (selectedRange is UTF-16 based; no String copy,
            // no components array).
            let text = textView.string
            let cursorPosition = min(textView.selectedRange().location, text.utf16.count)
            var cursorLine = 1
            for unit in text.utf16.prefix(cursorPosition) where unit == 0xA {
                cursorLine += 1
            }
            parent.onCursorLineChanged?(cursorLine)
        }
    }
}
#endif
