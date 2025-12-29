//
//  DictionaryLookupMenu.swift
//  MonkeyNote
//
//  Created by Nguyen Ngoc Khanh on 29/12/25.
//

#if os(macOS)
import SwiftUI
import AppKit

// MARK: - Dictionary Lookup Menu (triggered by typing "word\")

class DictionaryLookupWindowController: NSObject {
    private var window: NSPanel?
    private var backgroundView: NSView?
    private var scrollView: NSScrollView?
    private var textView: NSTextView?
    private var onDismiss: (() -> Void)?
    
    private var currentWord: String = ""
    private weak var parentWindow: NSWindow?
    private var menuOriginPoint: NSPoint = .zero
    
    private let menuWidth: CGFloat = 380
    private let menuMinHeight: CGFloat = 120
    private let menuMaxHeight: CGFloat = 400
    private let padding: CGFloat = 16
    
    func show(at point: NSPoint, in parentWindow: NSWindow?, word: String, onDismiss: @escaping () -> Void) {
        self.onDismiss = onDismiss
        self.currentWord = word
        self.menuOriginPoint = point
        self.parentWindow = parentWindow
        
        createWindow(word: word)
    }
    
    private func createWindow(word: String) {
        // Remove existing window if any
        if let existingWindow = window {
            existingWindow.parent?.removeChildWindow(existingWindow)
            existingWindow.orderOut(nil)
        }
        
        // Get definition
        let definition = DictionaryService.shared.getDefinition(for: word)
        
        // Build attributed content
        let attributedContent = buildAttributedContent(word: word, definition: definition)
        
        // Calculate height based on content
        let contentHeight = calculateContentHeight(attributedContent: attributedContent)
        let menuHeight = min(max(contentHeight + padding * 2, menuMinHeight), menuMaxHeight)
        
        // Calculate position
        var origin = NSPoint(x: menuOriginPoint.x, y: menuOriginPoint.y - menuHeight - 5)
        
        if let screen = NSScreen.main {
            let screenFrame = screen.visibleFrame
            if origin.x + menuWidth > screenFrame.maxX {
                origin.x = screenFrame.maxX - menuWidth - 10
            }
            if origin.x < screenFrame.minX {
                origin.x = screenFrame.minX + 10
            }
            if origin.y < screenFrame.minY {
                origin.y = menuOriginPoint.y + 25
            }
        }
        
        let panel = NSPanel(
            contentRect: NSRect(x: origin.x, y: origin.y, width: menuWidth, height: menuHeight),
            styleMask: [.nonactivatingPanel, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        panel.isOpaque = false
        panel.backgroundColor = NSColor.clear
        panel.hasShadow = true
        panel.level = NSWindow.Level.floating
        
        // Background view
        let bgView = NSView(frame: NSRect(x: 0, y: 0, width: menuWidth, height: menuHeight))
        bgView.wantsLayer = true
        bgView.layer?.cornerRadius = 10
        bgView.layer?.masksToBounds = true
        bgView.layer?.backgroundColor = NSColor(red: 38/255, green: 38/255, blue: 38/255, alpha: 0.98).cgColor
        bgView.layer?.borderWidth = 0.5
        bgView.layer?.borderColor = NSColor.white.withAlphaComponent(0.12).cgColor
        
        backgroundView = bgView
        
        // Setup scroll view with text
        setupScrollView(in: bgView, attributedContent: attributedContent, menuHeight: menuHeight)
        
        panel.contentView = bgView
        self.window = panel
        
        parentWindow?.addChildWindow(panel, ordered: NSWindow.OrderingMode.above)
        panel.makeKeyAndOrderFront(self)
    }
    
    private func setupScrollView(in container: NSView, attributedContent: NSAttributedString, menuHeight: CGFloat) {
        let scrollViewFrame = NSRect(
            x: padding,
            y: padding,
            width: menuWidth - padding * 2,
            height: menuHeight - padding * 2
        )
        
        let scroll = NSScrollView(frame: scrollViewFrame)
        scroll.hasVerticalScroller = true
        scroll.hasHorizontalScroller = false
        scroll.autohidesScrollers = true
        scroll.borderType = .noBorder
        scroll.backgroundColor = .clear
        scroll.drawsBackground = false
        
        let textViewFrame = NSRect(x: 0, y: 0, width: scrollViewFrame.width, height: scrollViewFrame.height)
        let text = NSTextView(frame: textViewFrame)
        text.isEditable = false
        text.isSelectable = true
        text.backgroundColor = .clear
        text.drawsBackground = false
        text.textContainerInset = NSSize(width: 0, height: 0)
        
        text.textContainer?.widthTracksTextView = true
        text.textContainer?.containerSize = NSSize(width: scrollViewFrame.width, height: .greatestFiniteMagnitude)
        text.isVerticallyResizable = true
        text.isHorizontallyResizable = false
        
        text.textStorage?.setAttributedString(attributedContent)
        
        scroll.documentView = text
        container.addSubview(scroll)
        
        scrollView = scroll
        textView = text
    }
    
    private func calculateContentHeight(attributedContent: NSAttributedString) -> CGFloat {
        let textStorage = NSTextStorage(attributedString: attributedContent)
        let textContainer = NSTextContainer(containerSize: NSSize(width: menuWidth - padding * 2, height: .greatestFiniteMagnitude))
        let layoutManager = NSLayoutManager()
        
        layoutManager.addTextContainer(textContainer)
        textStorage.addLayoutManager(layoutManager)
        
        textContainer.lineFragmentPadding = 0
        layoutManager.ensureLayout(for: textContainer)
        
        let usedRect = layoutManager.usedRect(for: textContainer)
        return usedRect.height
    }
    
    // MARK: - Build Attributed Content (Dictionary.app style)
    
    private func buildAttributedContent(word: String, definition: String?) -> NSAttributedString {
        let result = NSMutableAttributedString()
        
        // Word title (large, bold)
        let wordAttr = NSAttributedString(
            string: word.lowercased(),
            attributes: [
                .font: NSFont.systemFont(ofSize: 22, weight: .bold),
                .foregroundColor: NSColor.white
            ]
        )
        result.append(wordAttr)
        
        guard let definition = definition else {
            // No definition found
            result.append(NSAttributedString(string: "\n\n"))
            let noDefAttr = NSAttributedString(
                string: "No definition found",
                attributes: [
                    .font: NSFont.systemFont(ofSize: 13),
                    .foregroundColor: NSColor.white.withAlphaComponent(0.5)
                ]
            )
            result.append(noDefAttr)
            return result
        }
        
        // Parse and format the definition
        let parsed = parseDefinition(definition, word: word)
        
        // Pronunciation (if found)
        if !parsed.pronunciation.isEmpty {
            let pronAttr = NSAttributedString(
                string: "  " + parsed.pronunciation,
                attributes: [
                    .font: NSFont.systemFont(ofSize: 14),
                    .foregroundColor: NSColor.white.withAlphaComponent(0.5)
                ]
            )
            result.append(pronAttr)
        }
        
        result.append(NSAttributedString(string: "\n"))
        
        // Parts of speech and definitions
        for part in parsed.parts {
            result.append(NSAttributedString(string: "\n"))
            
            // Part of speech (e.g., "danh từ", "động từ")
            let posAttr = NSAttributedString(
                string: part.partOfSpeech,
                attributes: [
                    .font: NSFont.systemFont(ofSize: 12, weight: .medium),
                    .foregroundColor: NSColor.systemGray
                ]
            )
            result.append(posAttr)
            result.append(NSAttributedString(string: "\n"))
            
            // Definitions with numbers
            for (index, def) in part.definitions.enumerated() {
                let number = "\(index + 1) "
                let numberAttr = NSAttributedString(
                    string: number,
                    attributes: [
                        .font: NSFont.systemFont(ofSize: 13, weight: .semibold),
                        .foregroundColor: NSColor.white.withAlphaComponent(0.6)
                    ]
                )
                result.append(numberAttr)
                
                // Main definition text
                let defAttr = NSAttributedString(
                    string: def.text,
                    attributes: [
                        .font: NSFont.systemFont(ofSize: 14, weight: .medium),
                        .foregroundColor: NSColor.white
                    ]
                )
                result.append(defAttr)
                result.append(NSAttributedString(string: "\n"))
                
                // Examples (italic, indented)
                for example in def.examples {
                    let bulletAttr = NSAttributedString(
                        string: "    ▸ ",
                        attributes: [
                            .font: NSFont.systemFont(ofSize: 12),
                            .foregroundColor: NSColor.white.withAlphaComponent(0.4)
                        ]
                    )
                    result.append(bulletAttr)
                    
                    let exampleAttr = NSAttributedString(
                        string: example,
                        attributes: [
                            .font: NSFontManager.shared.convert(NSFont.systemFont(ofSize: 13), toHaveTrait: .italicFontMask),
                            .foregroundColor: NSColor.white.withAlphaComponent(0.6)
                        ]
                    )
                    result.append(exampleAttr)
                    result.append(NSAttributedString(string: "\n"))
                }
            }
        }
        
        // If no structured parts found, show raw definition
        if parsed.parts.isEmpty {
            let rawAttr = NSAttributedString(
                string: parsed.rawText,
                attributes: [
                    .font: NSFont.systemFont(ofSize: 13),
                    .foregroundColor: NSColor.white.withAlphaComponent(0.85)
                ]
            )
            result.append(rawAttr)
        }
        
        return result
    }
    
    // MARK: - Parse Definition
    
    private struct ParsedDefinition {
        var pronunciation: String = ""
        var parts: [PartOfSpeech] = []
        var rawText: String = ""
    }
    
    private struct PartOfSpeech {
        var partOfSpeech: String
        var definitions: [Definition]
    }
    
    private struct Definition {
        var text: String
        var examples: [String]
    }
    
    private func parseDefinition(_ definition: String, word: String) -> ParsedDefinition {
        var parsed = ParsedDefinition()
        parsed.rawText = definition
        
        // Extract pronunciation (usually in | | or / /)
        if let pipeMatch = definition.range(of: "\\|[^|]+\\|", options: .regularExpression) {
            parsed.pronunciation = String(definition[pipeMatch])
        } else if let slashMatch = definition.range(of: "/[^/]+/", options: .regularExpression) {
            parsed.pronunciation = String(definition[slashMatch])
        }
        
        // Try to identify parts of speech and definitions
        let partsOfSpeechPatterns = [
            ("noun", "danh từ"),
            ("verb", "động từ"),
            ("adjective", "tính từ"),
            ("adverb", "trạng từ"),
            ("pronoun", "đại từ"),
            ("preposition", "giới từ"),
            ("conjunction", "liên từ"),
            ("interjection", "thán từ"),
            ("determiner", "từ hạn định")
        ]
        
        var workingText = definition
        
        // Remove word and pronunciation from start
        let wordPattern = "^" + NSRegularExpression.escapedPattern(for: word) + "\\s*"
        if let regex = try? NSRegularExpression(pattern: wordPattern, options: .caseInsensitive) {
            workingText = regex.stringByReplacingMatches(in: workingText, options: [], range: NSRange(workingText.startIndex..., in: workingText), withTemplate: "")
        }
        if !parsed.pronunciation.isEmpty {
            workingText = workingText.replacingOccurrences(of: parsed.pronunciation, with: "")
        }
        
        // Look for part of speech markers
        for (english, vietnamese) in partsOfSpeechPatterns {
            // Check if this part of speech exists in the text
            let patterns = [
                "\\b\(english)\\b",
                "\\b\(vietnamese)\\b"
            ]
            
            for pattern in patterns {
                if let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive),
                   regex.firstMatch(in: workingText, options: [], range: NSRange(workingText.startIndex..., in: workingText)) != nil {
                    
                    // Found this part of speech - extract definitions following it
                    var part = PartOfSpeech(partOfSpeech: vietnamese, definitions: [])
                    
                    // For simplicity, extract numbered definitions (1, 2, 3...)
                    let numberedPattern = "(?:^|\\s)(\\d+)[.\\s]+([^\\d]+?)(?=\\s*\\d+[.\\s]|$)"
                    if let numRegex = try? NSRegularExpression(pattern: numberedPattern, options: [.dotMatchesLineSeparators]) {
                        let matches = numRegex.matches(in: workingText, options: [], range: NSRange(workingText.startIndex..., in: workingText))
                        
                        for match in matches.prefix(5) { // Limit to 5 definitions
                            if match.numberOfRanges >= 3,
                               let defRange = Range(match.range(at: 2), in: workingText) {
                                let defText = String(workingText[defRange]).trimmingCharacters(in: .whitespacesAndNewlines)
                                if !defText.isEmpty && defText.count > 2 {
                                    // Look for examples (often after • or ▸ or in parentheses)
                                    var mainDef = defText
                                    var examples: [String] = []
                                    
                                    // Split by common example markers
                                    let exampleMarkers = ["•", "▸", "‣", "→"]
                                    for marker in exampleMarkers {
                                        if mainDef.contains(marker) {
                                            let parts = mainDef.components(separatedBy: marker)
                                            mainDef = parts[0].trimmingCharacters(in: .whitespacesAndNewlines)
                                            examples = Array(parts.dropFirst()).map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                                            break
                                        }
                                    }
                                    
                                    part.definitions.append(Definition(text: mainDef, examples: examples))
                                }
                            }
                        }
                    }
                    
                    if !part.definitions.isEmpty {
                        parsed.parts.append(part)
                    }
                    break
                }
            }
        }
        
        // If no structured parsing worked, create a simple view
        if parsed.parts.isEmpty {
            // Clean up raw text
            parsed.rawText = workingText
                .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            
            // Limit length
            if parsed.rawText.count > 500 {
                let endIndex = parsed.rawText.index(parsed.rawText.startIndex, offsetBy: 500)
                parsed.rawText = String(parsed.rawText[..<endIndex]) + "..."
            }
        }
        
        return parsed
    }
    
    func updateWord(_ word: String) {
        currentWord = word
        if parentWindow != nil {
            createWindow(word: word)
        }
    }
    
    func dismiss() {
        if let window = self.window {
            window.parent?.removeChildWindow(window)
            window.orderOut(nil)
        }
        self.window = nil
        self.backgroundView = nil
        self.scrollView = nil
        self.textView = nil
        onDismiss?()
    }
    
    var isVisible: Bool {
        window != nil
    }
    
    var currentLookupWord: String {
        currentWord
    }
}
#endif
