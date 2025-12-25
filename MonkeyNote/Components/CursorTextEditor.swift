//
//  ThickCursorTextEditor.swift
//  Note
//
//  Created by Nguyen Ngoc Khanh on 24/12/25.
//

#if os(macOS)
import SwiftUI
import AppKit

// MARK: - Word Suggestion Manager
class WordSuggestionManager {
    static let shared = WordSuggestionManager()
    private var bundledWords: [String] = []
    private var customWords: [String] = []
    private var customFolderURL: URL?
    private var useBuiltIn: Bool = true
    private var minWordLength: Int = 4
    
    private init() {
        loadBundledWords()
        loadCustomWordsFromUserDefaults()
        useBuiltIn = UserDefaults.standard.object(forKey: "note.useBuiltInDictionary") as? Bool ?? true
        minWordLength = UserDefaults.standard.object(forKey: "note.minWordLength") as? Int ?? 4
    }
    
    private func loadBundledWords() {
        // Load from bundled word.txt file
        if let path = Bundle.main.path(forResource: "word", ofType: "txt"),
           let content = try? String(contentsOfFile: path, encoding: .utf8) {
            bundledWords = parseWords(from: content)
        }
    }
    
    private func loadCustomWordsFromUserDefaults() {
        // Load custom folder path from UserDefaults
        if let bookmarkData = UserDefaults.standard.data(forKey: "note.customWordFolderBookmark") {
            do {
                var isStale = false
                let url = try URL(resolvingBookmarkData: bookmarkData, options: .withSecurityScope, relativeTo: nil, bookmarkDataIsStale: &isStale)
                if url.startAccessingSecurityScopedResource() {
                    customFolderURL = url
                    loadCustomWords(from: url)
                }
            } catch {
                print("Failed to resolve bookmark: \(error)")
            }
        }
    }
    
    func setUseBuiltIn(_ value: Bool) {
        useBuiltIn = value
    }
    
    func setMinWordLength(_ value: Int) {
        minWordLength = value
    }
    
    func setCustomFolder(_ url: URL?) {
        // Stop accessing previous folder
        customFolderURL?.stopAccessingSecurityScopedResource()
        
        if let url = url {
            // Save bookmark for security-scoped access
            do {
                let bookmarkData = try url.bookmarkData(options: .withSecurityScope, includingResourceValuesForKeys: nil, relativeTo: nil)
                UserDefaults.standard.set(bookmarkData, forKey: "note.customWordFolderBookmark")
                customFolderURL = url
                loadCustomWords(from: url)
            } catch {
                print("Failed to create bookmark: \(error)")
            }
        } else {
            UserDefaults.standard.removeObject(forKey: "note.customWordFolderBookmark")
            customFolderURL = nil
            customWords = []
        }
    }
    
    func getCustomFolderURL() -> URL? {
        return customFolderURL
    }
    
    private func loadCustomWords(from folderURL: URL) {
        customWords = []
        
        let fileManager = FileManager.default
        guard let enumerator = fileManager.enumerator(at: folderURL, includingPropertiesForKeys: [.isRegularFileKey], options: [.skipsHiddenFiles]) else {
            return
        }
        
        for case let fileURL as URL in enumerator {
            if fileURL.pathExtension.lowercased() == "txt" {
                if let content = try? String(contentsOf: fileURL, encoding: .utf8) {
                    let words = parseWords(from: content)
                    customWords.append(contentsOf: words)
                }
            }
        }
        
        // Remove duplicates
        customWords = Array(Set(customWords))
    }
    
    func reloadCustomWords() {
        if let url = customFolderURL {
            loadCustomWords(from: url)
        }
    }
    
    private func parseWords(from content: String) -> [String] {
        // Parse words separated by commas, newlines, and spaces
        return content
            .components(separatedBy: CharacterSet(charactersIn: ",\n "))
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty && $0.count >= 2 }
    }
    
    private var allWords: [String] {
        var words: [String] = []
        if useBuiltIn {
            words.append(contentsOf: bundledWords)
        }
        words.append(contentsOf: customWords)
        return words
    }
    
    func getSuggestion(for prefix: String) -> String? {
        guard !prefix.isEmpty else { return nil }
        let lowercasedPrefix = prefix.lowercased()
        
        // Find first word that starts with the prefix and meets minimum length
        if let match = allWords.first(where: { 
            $0.lowercased().hasPrefix(lowercasedPrefix) && 
            $0.lowercased() != lowercasedPrefix &&
            $0.count >= minWordLength  // Filter by minimum word length
        }) {
            // Return only the completion part (without the prefix)
            let completionStartIndex = match.index(match.startIndex, offsetBy: prefix.count)
            return String(match[completionStartIndex...])
        }
        return nil
    }
    
    // MARK: - Sentence Suggestion (Beta)
    func getSentenceSuggestion() -> String {
        // TODO: Replace this with actual sentence suggestion logic
        // This is a placeholder for future development
        return "this is a test version of the sentence suggestion feature"
    }
    
    var customWordCount: Int {
        return customWords.count
    }
    
    var bundledWordCount: Int {
        return bundledWords.count
    }
}

private class ThickCursorLayoutManager: NSLayoutManager {
    var cursorWidth: CGFloat = 6
}

private class ThickCursorTextView: NSTextView {
    var cursorWidth: CGFloat = 6
    var cursorBlinkEnabled: Bool = true
    var cursorAnimationEnabled: Bool = true
    var cursorAnimationDuration: Double = 0.15
    var searchText: String = ""
    var autocompleteEnabled: Bool = true
    var autocompleteDelay: Double = 0.0
    var autocompleteOpacity: Double = 0.5
    var suggestionMode: String = "word"  // "word" or "sentence"
    private var cursorLayer: CALayer?
    private var lastCursorRect: NSRect = .zero
    private var highlightLayers: [CALayer] = []
    
    // Slash command menu
    private var slashCommandController = SlashCommandWindowController()
    private var slashCommandRange: NSRange?
    
    // Autocomplete ghost text
    private var ghostTextLayer: CATextLayer?
    private var currentSuggestion: String?
    private var suggestionWordStart: Int = 0
    private var suggestionTask: Task<Void, Never>?
    
    // Selection toolbar
    private var selectionToolbarController = SelectionToolbarController.shared

    override func drawInsertionPoint(in rect: NSRect, color: NSColor, turnedOn flag: Bool) {
        let shouldDraw = cursorBlinkEnabled ? flag : true
        guard shouldDraw else {
            cursorLayer?.opacity = 0
            return
        }

        var thickRect = rect
        thickRect.size.width = cursorWidth

        if cursorLayer == nil {
            let layer = CALayer()
            layer.cornerRadius = cursorWidth / 2
            layer.backgroundColor = color.cgColor
            wantsLayer = true
            self.layer?.addSublayer(layer)
            cursorLayer = layer
        }

        cursorLayer?.backgroundColor = color.cgColor
        cursorLayer?.cornerRadius = cursorWidth / 2

        if lastCursorRect != thickRect {
            if cursorAnimationEnabled {
                CATransaction.begin()
                CATransaction.setAnimationDuration(cursorAnimationDuration)
                CATransaction.setAnimationTimingFunction(CAMediaTimingFunction(name: .easeOut))
                cursorLayer?.frame = thickRect
                cursorLayer?.opacity = 1
                CATransaction.commit()
            } else {
                cursorLayer?.frame = thickRect
                cursorLayer?.opacity = 1
            }
            lastCursorRect = thickRect
        } else {
            cursorLayer?.frame = thickRect
            cursorLayer?.opacity = 1
        }
    }

    override func setNeedsDisplay(_ invalidRect: NSRect, avoidAdditionalLayout flag: Bool) {
        var extendedRect = invalidRect
        extendedRect.size.width += cursorWidth
        super.setNeedsDisplay(extendedRect, avoidAdditionalLayout: flag)
    }

    override func resignFirstResponder() -> Bool {
        let didResign = super.resignFirstResponder()
        cursorLayer?.opacity = 0
        return didResign
    }

    override var rangeForUserCompletion: NSRange {
        selectedRange()
    }

    func updateHighlights() {
        self.highlightLayers.forEach { $0.removeFromSuperlayer() }
        self.highlightLayers.removeAll()

        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty, let layoutManager = layoutManager, let textContainer = textContainer else { return }

        let text = self.string
        var searchRange = NSRange(location: 0, length: text.utf16.count)

        while searchRange.location < text.utf16.count {
            let foundRange = (text as NSString).range(of: query, options: .caseInsensitive, range: searchRange)

            if foundRange.location == NSNotFound {
                break
            }

            let glyphRange = layoutManager.glyphRange(forCharacterRange: foundRange, actualCharacterRange: nil)
            layoutManager.enumerateEnclosingRects(forGlyphRange: glyphRange, withinSelectedGlyphRange: glyphRange, in: textContainer) { rect, _ in
                let highlightLayer = CALayer()
                highlightLayer.backgroundColor = NSColor.yellow.withAlphaComponent(0.3).cgColor
                highlightLayer.cornerRadius = 2
                highlightLayer.frame = rect
                self.layer?.addSublayer(highlightLayer)
                self.highlightLayers.append(highlightLayer)
            }

            searchRange.location = foundRange.location + foundRange.length
            searchRange.length = text.utf16.count - searchRange.location
        }
    }
    
    // MARK: - Autocomplete Ghost Text
    private func updateSuggestion() {
        // Check if autocomplete is enabled
        guard autocompleteEnabled else {
            hideSuggestion()
            return
        }
        
        // Cancel any pending suggestion task
        suggestionTask?.cancel()
        
        // If delay is 0, show immediately
        if autocompleteDelay <= 0 {
            performSuggestionUpdate()
        } else {
            // Debounce with delay
            suggestionTask = Task {
                try? await Task.sleep(nanoseconds: UInt64(autocompleteDelay * 1_000_000_000))
                guard !Task.isCancelled else { return }
                await MainActor.run {
                    performSuggestionUpdate()
                }
            }
        }
    }
    
    private func performSuggestionUpdate() {
        let selectedRange = self.selectedRange()
        let text = self.string as NSString
        
        // Only suggest when cursor is at the end of a word (no selection)
        guard selectedRange.length == 0 else {
            hideSuggestion()
            return
        }
        
        let cursorPosition = selectedRange.location
        guard cursorPosition > 0 else {
            hideSuggestion()
            return
        }
        
        // Check suggestion mode
        if suggestionMode == "sentence" {
            // Sentence mode: always show beta message
            let suggestion = WordSuggestionManager.shared.getSentenceSuggestion()
            currentSuggestion = suggestion
            suggestionWordStart = cursorPosition
            showGhostText(suggestion, at: cursorPosition)
            return
        }
        
        // Word mode: find word and suggest completion
        // Find word start
        var wordStart = cursorPosition
        while wordStart > 0 {
            let charIndex = wordStart - 1
            let char = text.substring(with: NSRange(location: charIndex, length: 1))
            if char.rangeOfCharacter(from: CharacterSet.alphanumerics) == nil {
                break
            }
            wordStart -= 1
        }
        
        // Get the current word prefix
        let wordLength = cursorPosition - wordStart
        guard wordLength >= 2 else { // Only suggest after 2+ characters
            hideSuggestion()
            return
        }
        
        let currentWord = text.substring(with: NSRange(location: wordStart, length: wordLength))
        
        // Get suggestion
        if let suggestion = WordSuggestionManager.shared.getSuggestion(for: currentWord) {
            currentSuggestion = suggestion
            suggestionWordStart = wordStart
            showGhostText(suggestion, at: cursorPosition)
        } else {
            hideSuggestion()
        }
    }
    
    private func showGhostText(_ text: String, at position: Int) {
        guard let layoutManager = layoutManager,
              let textContainer = textContainer else { return }
        
        // Get cursor position rect
        let glyphRange = layoutManager.glyphRange(forCharacterRange: NSRange(location: position, length: 0), actualCharacterRange: nil)
        var cursorRect = layoutManager.boundingRect(forGlyphRange: glyphRange, in: textContainer)
        cursorRect.origin.x += textContainerInset.width
        cursorRect.origin.y += textContainerInset.height
        
        // Create or update ghost text layer
        if ghostTextLayer == nil {
            let layer = CATextLayer()
            layer.contentsScale = NSScreen.main?.backingScaleFactor ?? 2.0
            layer.alignmentMode = .left
            wantsLayer = true
            self.layer?.addSublayer(layer)
            ghostTextLayer = layer
        }
        
        // Disable all animations for ghost text
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        
        // Configure the ghost text with opacity from settings
        let font = self.font ?? NSFont.systemFont(ofSize: 14)
        ghostTextLayer?.font = font
        ghostTextLayer?.fontSize = font.pointSize
        ghostTextLayer?.foregroundColor = NSColor.gray.withAlphaComponent(autocompleteOpacity).cgColor
        ghostTextLayer?.string = text
        
        // Calculate size for the ghost text
        let attributes: [NSAttributedString.Key: Any] = [.font: font]
        let textSize = (text as NSString).size(withAttributes: attributes)
        
        // Position ghost text right after cursor
        ghostTextLayer?.frame = NSRect(
            x: cursorRect.origin.x + cursorWidth,
            y: cursorRect.origin.y,
            width: textSize.width + 10,
            height: cursorRect.height
        )
        ghostTextLayer?.isHidden = false
        
        CATransaction.commit()
    }
    
    private func hideSuggestion() {
        suggestionTask?.cancel()
        
        // Disable animation when hiding
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        ghostTextLayer?.isHidden = true
        CATransaction.commit()
        
        currentSuggestion = nil
    }
    
    func acceptSuggestion() -> Bool {
        guard let suggestion = currentSuggestion, !suggestion.isEmpty else {
            return false
        }
        
        // Insert the suggestion at cursor position
        let selectedRange = self.selectedRange()
        replaceCharacters(in: selectedRange, with: suggestion)
        
        // Move cursor to end of inserted text
        let newPosition = selectedRange.location + suggestion.utf16.count
        setSelectedRange(NSRange(location: newPosition, length: 0))
        
        hideSuggestion()
        return true
    }
    
    // MARK: - Slash Command Menu
    private func showSlashMenu() {
        guard let layoutManager = layoutManager,
              let textContainer = textContainer,
              let window = self.window else { return }
        
        let selectedRange = self.selectedRange()
        slashCommandRange = NSRange(location: selectedRange.location - 1, length: 1) // The "/" character
        
        // Get cursor position in window coordinates
        let glyphRange = layoutManager.glyphRange(forCharacterRange: selectedRange, actualCharacterRange: nil)
        var cursorRect = layoutManager.boundingRect(forGlyphRange: glyphRange, in: textContainer)
        cursorRect.origin.x += textContainerInset.width
        cursorRect.origin.y += textContainerInset.height
        
        // Convert to window coordinates
        let rectInView = convert(cursorRect, to: nil)
        let rectInWindow = window.convertToScreen(NSRect(origin: rectInView.origin, size: CGSize(width: 1, height: cursorRect.height)))
        
        slashCommandController.show(
            at: NSPoint(x: rectInWindow.origin.x, y: rectInWindow.origin.y),
            in: window,
            onSelect: { [weak self] command in
                self?.handleSlashCommand(command)
            },
            onDismiss: { [weak self] in
                self?.slashCommandRange = nil
            }
        )
    }
    
    private func dismissSlashMenu() {
        slashCommandController.dismiss()
        slashCommandRange = nil
    }
    
    private func handleSlashCommand(_ command: SlashCommand) {
        guard let range = slashCommandRange else { return }
        
        // Delete the "/" character and insert the list prefix
        let text = self.string as NSString
        let lineRange = text.lineRange(for: range)
        let lineStart = lineRange.location
        
        // Replace from line start to after "/" with the command prefix
        let rangeToReplace = NSRange(location: lineStart, length: range.location + range.length - lineStart)
        replaceCharacters(in: rangeToReplace, with: command.prefix)
        
        let newCursorPosition = lineStart + command.prefix.utf16.count
        setSelectedRange(NSRange(location: newCursorPosition, length: 0))
        
        slashCommandRange = nil
    }

    override func keyDown(with event: NSEvent) {
        // Handle slash command menu navigation
        if slashCommandController.isVisible {
            switch event.keyCode {
            case 126: // Up arrow
                slashCommandController.moveUp()
                return
            case 125: // Down arrow
                slashCommandController.moveDown()
                return
            case 36: // Enter
                slashCommandController.selectCurrent()
                return
            case 53: // Escape
                dismissSlashMenu()
                return
            default:
                // Any other key dismisses menu
                dismissSlashMenu()
            }
        }
        
        // Handle Escape to dismiss autocomplete suggestion
        if event.keyCode == 53 { // Escape
            if currentSuggestion != nil {
                hideSuggestion()
                return
            }
        }
        
        guard !event.isARepeat else {
            super.keyDown(with: event)
            return
        }
        
        // Handle Tab key - check for autocomplete suggestion first
        if event.keyCode == 48 {
            // Try to accept autocomplete suggestion first
            if acceptSuggestion() {
                return
            }
            
            let selectedRange = self.selectedRange()
            let text = self.string as NSString
            
            // Check if character BEFORE cursor is "-"
            if selectedRange.location > 0 {
                let prevCharIndex = selectedRange.location - 1
                if prevCharIndex < text.length {
                    let prevChar = text.substring(with: NSRange(location: prevCharIndex, length: 1))
                    if prevChar == "-" {
                        // Get the rest of the line after the dash
                        let lineRange = text.lineRange(for: NSRange(location: prevCharIndex, length: 0))
                        let rangeAfterDash = NSRange(location: prevCharIndex + 1, length: lineRange.location + lineRange.length - prevCharIndex - 1)
                        let remainingText = text.substring(with: rangeAfterDash)
                        
                        // Replace the entire line from dash to end with bullet + remaining text
                        let lineAfterDash = NSRange(location: prevCharIndex, length: lineRange.location + lineRange.length - prevCharIndex)
                        let newText = "• " + remainingText.trimmingCharacters(in: .whitespacesAndNewlines)
                        self.replaceCharacters(in: lineAfterDash, with: newText)
                        self.setSelectedRange(NSRange(location: prevCharIndex + newText.utf16.count, length: 0))
                        return
                    }
                    
                    // Check for numbered list pattern like "1."
                    if prevCharIndex >= 1 {
                        let twoCharsBefore = text.substring(with: NSRange(location: prevCharIndex - 1, length: 2))
                        if let regex = try? NSRegularExpression(pattern: "^\\d\\.", options: []),
                           regex.firstMatch(in: twoCharsBefore, options: [], range: NSRange(location: 0, length: 2)) != nil {
                            let lineRange = text.lineRange(for: NSRange(location: prevCharIndex - 1, length: 0))
                            let rangeAfterNumber = NSRange(location: prevCharIndex + 1, length: lineRange.location + lineRange.length - prevCharIndex - 1)
                            let remainingText = text.substring(with: rangeAfterNumber)
                            
                            // Replace the entire line from number to end with proper numbered list format
                            let lineAfterNumber = NSRange(location: prevCharIndex - 1, length: lineRange.location + lineRange.length - (prevCharIndex - 1))
                            let newText = twoCharsBefore + " " + remainingText.trimmingCharacters(in: .whitespacesAndNewlines)
                            self.replaceCharacters(in: lineAfterNumber, with: newText)
                            self.setSelectedRange(NSRange(location: prevCharIndex - 1 + newText.utf16.count, length: 0))
                            return
                        }
                    }
                }
            }
            
            super.insertText("\t")
            return
        }
        
        if event.keyCode == 36 {
            let selectedRange = self.selectedRange()
            let text = self.string as NSString
            
            let lineRange = text.lineRange(for: selectedRange)
            let currentLine = text.substring(with: lineRange)
            let trimmedLine = currentLine.trimmingCharacters(in: .whitespaces)
            
            if trimmedLine.hasPrefix("•") {
                // Get content after bullet (handle both "• " and "•")
                var bulletContent: String
                if trimmedLine.hasPrefix("• ") {
                    bulletContent = String(trimmedLine.dropFirst("• ".count)).trimmingCharacters(in: .whitespaces)
                } else {
                    bulletContent = String(trimmedLine.dropFirst("•".count)).trimmingCharacters(in: .whitespaces)
                }
                
                if bulletContent.isEmpty {
                    // Remove the bullet line entirely
                    let linesBefore = text.substring(with: NSRange(location: 0, length: lineRange.location))
                    let linesAfter = text.substring(with: NSRange(location: lineRange.location + lineRange.length, length: text.length - (lineRange.location + lineRange.length)))
                    let newString = linesBefore + linesAfter
                    self.string = newString
                    self.setSelectedRange(NSRange(location: lineRange.location, length: 0))
                } else {
                    super.insertText("\n• ")
                    self.setSelectedRange(NSRange(location: selectedRange.location + "\n• ".utf16.count, length: 0))
                }
                return
            }
            
            // Handle numbered list
            if let regex = try? NSRegularExpression(pattern: "^(\\d+)\\.", options: []),
               let match = regex.firstMatch(in: trimmedLine, options: [], range: NSRange(location: 0, length: trimmedLine.utf16.count)) {
                let numberRange = match.range(at: 1)
                let numberString = (trimmedLine as NSString).substring(with: numberRange)
                let number = Int(numberString) ?? 1
                let contentStart = match.range.location + match.range.length
                let contentLength = trimmedLine.utf16.count - contentStart
                let content = (trimmedLine as NSString).substring(with: NSRange(location: contentStart, length: contentLength)).trimmingCharacters(in: .whitespaces)
                
                if content.isEmpty {
                    let linesBefore = text.substring(with: NSRange(location: 0, length: lineRange.location))
                    let linesAfter = text.substring(with: NSRange(location: lineRange.location + lineRange.length, length: text.length - (lineRange.location + lineRange.length)))
                    let newString = linesBefore + linesAfter
                    self.string = newString
                    self.setSelectedRange(NSRange(location: lineRange.location, length: 0))
                } else {
                    let nextNumber = number + 1
                    let nextLineText = "\n\(nextNumber). "
                    super.insertText(nextLineText)
                    self.setSelectedRange(NSRange(location: selectedRange.location + nextLineText.utf16.count, length: 0))
                }
                return
            }
        }
        
        super.keyDown(with: event)
    }
    
    override func insertText(_ insertString: Any, replacementRange: NSRange) {
        super.insertText(insertString, replacementRange: replacementRange)
        
        // Update cursor position in MarkdownTextStorage
        if let textStorage = self.textStorage as? MarkdownTextStorage {
            textStorage.cursorPosition = self.selectedRange().location
        }
        
        // Update autocomplete suggestion
        if let str = insertString as? String {
            // Hide suggestion if space or punctuation is typed
            if str.rangeOfCharacter(from: CharacterSet.alphanumerics) == nil {
                hideSuggestion()
            } else {
                updateSuggestion()
            }
        }
        
        // Check if "/" was typed at the beginning of a line
        guard let str = insertString as? String, str == "/" else { return }
        
        let selectedRange = self.selectedRange()
        let text = self.string as NSString
        
        // Check if "/" is at the start of a line (after newline or at position 0)
        let slashPosition = selectedRange.location - 1
        if slashPosition < 0 { return }
        
        let isAtLineStart: Bool
        if slashPosition == 0 {
            isAtLineStart = true
        } else {
            let prevChar = text.substring(with: NSRange(location: slashPosition - 1, length: 1))
            isAtLineStart = prevChar == "\n"
        }
        
        if isAtLineStart {
            showSlashMenu()
        }
    }
    
    override func deleteBackward(_ sender: Any?) {
        super.deleteBackward(sender)
        
        // Update cursor position in MarkdownTextStorage
        if let textStorage = self.textStorage as? MarkdownTextStorage {
            textStorage.cursorPosition = self.selectedRange().location
        }
        
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
    
    private func handleSelectionChange() {
        let selectedRange = self.selectedRange()
        
        // Update cursor position in MarkdownTextStorage for syntax visibility
        if let textStorage = self.textStorage as? MarkdownTextStorage {
            textStorage.cursorPosition = selectedRange.location
        }
        
        // Only show toolbar when there's a selection (not just cursor)
        if selectedRange.length > 0 {
            showSelectionToolbar(for: selectedRange)
        } else {
            selectionToolbarController.dismiss()
        }
    }
    
    private func showSelectionToolbar(for range: NSRange) {
        guard let layoutManager = layoutManager,
              let textContainer = textContainer,
              let window = self.window else { return }
        
        // Get the rect of the selected text
        let glyphRange = layoutManager.glyphRange(forCharacterRange: range, actualCharacterRange: nil)
        var selectionRect = layoutManager.boundingRect(forGlyphRange: glyphRange, in: textContainer)
        selectionRect.origin.x += textContainerInset.width
        selectionRect.origin.y += textContainerInset.height
        
        // Convert to window coordinates
        let rectInView = convert(selectionRect, to: nil)
        let rectInScreen = window.convertToScreen(NSRect(
            origin: rectInView.origin,
            size: CGSize(width: selectionRect.width, height: selectionRect.height)
        ))
        
        // Position toolbar above the selection (centered)
        let toolbarPoint = NSPoint(
            x: rectInScreen.midX,
            y: rectInScreen.maxY
        )
        
        selectionToolbarController.show(
            at: toolbarPoint,
            in: window,
            selectionRange: range,
            onAction: { [weak self] (action: ToolbarAction, selectionRange: NSRange) in
                self?.applyFormatting(action: action, range: selectionRange)
            }
        )
    }
    
    private func applyFormatting(action: ToolbarAction, range: NSRange) {
        let text = self.string as NSString
        let selectedText = text.substring(with: range)
        
        var newText = selectedText
        
        switch action {
        case .bold:
            newText = "**\(selectedText)**"
        case .italic:
            newText = "_\(selectedText)_"
        case .underline:
            newText = "<u>\(selectedText)</u>"
        case .strikethrough:
            newText = "~~\(selectedText)~~"
        case .highlight:
            newText = "==\(selectedText)=="
        case .link:
            newText = "[\(selectedText)](url)"
        case .heading:
            // Add heading marker at the beginning of line
            let lineRange = text.lineRange(for: range)
            let lineStart = lineRange.location
            let currentLine = text.substring(with: lineRange)
            
            if currentLine.hasPrefix("### ") {
                // Remove heading
                replaceCharacters(in: NSRange(location: lineStart, length: 4), with: "")
            } else if currentLine.hasPrefix("## ") {
                // H2 -> H3
                replaceCharacters(in: NSRange(location: lineStart, length: 3), with: "### ")
            } else if currentLine.hasPrefix("# ") {
                // H1 -> H2
                replaceCharacters(in: NSRange(location: lineStart, length: 2), with: "## ")
            } else {
                // Add H1
                replaceCharacters(in: NSRange(location: lineStart, length: 0), with: "# ")
            }
            return
        case .list:
            // Add bullet at the beginning of line
            let lineRange = text.lineRange(for: range)
            let lineStart = lineRange.location
            let currentLine = text.substring(with: lineRange)
            
            if currentLine.hasPrefix("• ") || currentLine.hasPrefix("- ") {
                // Remove bullet
                replaceCharacters(in: NSRange(location: lineStart, length: 2), with: "")
            } else {
                // Add bullet
                replaceCharacters(in: NSRange(location: lineStart, length: 0), with: "• ")
            }
            return
        case .alignLeft:
            // Alignment is not typically supported in plain markdown
            return
        case .askAI:
            // TODO: Implement AI feature
            print("Ask AI with selected text: \(selectedText)")
            return
        }
        
        // Replace selected text with formatted text
        replaceCharacters(in: range, with: newText)
        
        // Update cursor position
        let newCursorPosition = range.location + newText.utf16.count
        setSelectedRange(NSRange(location: newCursorPosition, length: 0))
    }
    
    override func layout() {
        super.layout()
        updateHighlights()
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

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.borderType = .noBorder
        scrollView.drawsBackground = false

        let layoutManager = ThickCursorLayoutManager()
        layoutManager.cursorWidth = cursorWidth

        // Use MarkdownTextStorage for live markdown rendering
        let textStorage = MarkdownTextStorage()
        textStorage.addLayoutManager(layoutManager)

        let textContainer = NSTextContainer()
        textContainer.widthTracksTextView = true
        textContainer.containerSize = NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude)
        layoutManager.addTextContainer(textContainer)

        let textView = ThickCursorTextView(frame: .zero, textContainer: textContainer)
        textView.cursorWidth = cursorWidth
        textView.cursorBlinkEnabled = cursorBlinkEnabled
        textView.cursorAnimationEnabled = cursorAnimationEnabled
        textView.cursorAnimationDuration = cursorAnimationDuration
        textView.searchText = searchText
        textView.autocompleteEnabled = autocompleteEnabled
        textView.autocompleteDelay = autocompleteDelay
        textView.autocompleteOpacity = autocompleteOpacity
        textView.suggestionMode = suggestionMode
        textView.isRichText = true  // Enable rich text for markdown styling
        textView.allowsUndo = true
        textView.isEditable = true
        textView.isSelectable = true
        textView.drawsBackground = false
        textView.textContainerInset = NSSize(width: horizontalPadding, height: 0)
        
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
        
        // Configure MarkdownTextStorage with base font and color
        textStorage.baseFont = font
        textStorage.baseTextColor = isDarkMode
            ? NSColor.white.withAlphaComponent(0.92)
            : NSColor.black.withAlphaComponent(0.92)
        
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
        
        // Trigger initial markdown processing
        textStorage.reprocessMarkdown()

        scrollView.documentView = textView
        context.coordinator.textView = textView

        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? ThickCursorTextView else { return }

        if textView.string != text {
            let selectedRange = textView.selectedRange()
            textView.string = text
            let safeLocation = min(selectedRange.location, text.utf16.count)
            let safeLength = min(selectedRange.length, text.utf16.count - safeLocation)
            textView.setSelectedRange(NSRange(location: safeLocation, length: safeLength))
            
            // Reprocess markdown when text changes externally
            if let textStorage = textView.textStorage as? MarkdownTextStorage {
                textStorage.reprocessMarkdown()
            }
        }

        textView.cursorWidth = cursorWidth
        textView.cursorBlinkEnabled = cursorBlinkEnabled
        textView.cursorAnimationEnabled = cursorAnimationEnabled
        textView.cursorAnimationDuration = cursorAnimationDuration
        textView.searchText = searchText
        textView.autocompleteEnabled = autocompleteEnabled
        textView.autocompleteDelay = autocompleteDelay
        textView.autocompleteOpacity = autocompleteOpacity
        textView.suggestionMode = suggestionMode
        if let layoutManager = textView.layoutManager as? ThickCursorLayoutManager {
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
        textView.font = font
        
        let textColor = isDarkMode
            ? NSColor.white.withAlphaComponent(0.92)
            : NSColor.black.withAlphaComponent(0.92)

        textView.textColor = textColor
        textView.insertionPointColor = NSColor(
            red: 222.0 / 255.0,
            green: 99.0 / 255.0,
            blue: 74.0 / 255.0,
            alpha: 1.0
        )
        
        // Update MarkdownTextStorage settings
        if let textStorage = textView.textStorage as? MarkdownTextStorage {
            let needsReprocess = textStorage.baseFont != font || textStorage.baseTextColor != textColor
            textStorage.baseFont = font
            textStorage.baseTextColor = textColor
            if needsReprocess {
                textStorage.reprocessMarkdown()
            }
        }

        textView.updateHighlights()
    }

    class Coordinator: NSObject, NSTextViewDelegate {
        var parent: ThickCursorTextEditor
        fileprivate weak var textView: ThickCursorTextView?

        init(_ parent: ThickCursorTextEditor) {
            self.parent = parent
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            parent.text = textView.string
            
            // Update cursor position in MarkdownTextStorage
            if let textStorage = textView.textStorage as? MarkdownTextStorage {
                textStorage.cursorPosition = textView.selectedRange().location
            }
            
            // Auto-scroll to cursor position with smooth animation
            guard let scrollView = textView.enclosingScrollView,
                  let layoutManager = textView.layoutManager,
                  let textContainer = textView.textContainer else { return }
            
            let selectedRange = textView.selectedRange()
            let glyphRange = layoutManager.glyphRange(forCharacterRange: selectedRange, actualCharacterRange: nil)
            let cursorRect = layoutManager.boundingRect(forGlyphRange: glyphRange, in: textContainer)
            
            let cursorY = cursorRect.origin.y + textView.textContainerInset.height
            let cursorHeight = max(cursorRect.height, textView.font?.pointSize ?? 16)
            let visibleRect = scrollView.documentVisibleRect
            let padding: CGFloat = 20
            
            // Check if cursor is below visible area
            if cursorY + cursorHeight > visibleRect.maxY - padding {
                let newY = cursorY + cursorHeight - visibleRect.height + padding
                let targetPoint = NSPoint(x: 0, y: max(0, newY))
                
                NSAnimationContext.runAnimationGroup { context in
                    context.duration = 0.15
                    context.timingFunction = CAMediaTimingFunction(name: .easeOut)
                    scrollView.contentView.animator().setBoundsOrigin(targetPoint)
                }
            }
            // Check if cursor is above visible area
            else if cursorY < visibleRect.minY + padding {
                let targetPoint = NSPoint(x: 0, y: max(0, cursorY - padding))
                
                NSAnimationContext.runAnimationGroup { context in
                    context.duration = 0.15
                    context.timingFunction = CAMediaTimingFunction(name: .easeOut)
                    scrollView.contentView.animator().setBoundsOrigin(targetPoint)
                }
            }
        }
        
        func textViewDidChangeSelection(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            
            // Update cursor position in MarkdownTextStorage for syntax visibility
            if let textStorage = textView.textStorage as? MarkdownTextStorage {
                textStorage.cursorPosition = textView.selectedRange().location
            }
        }
    }
}
#endif
