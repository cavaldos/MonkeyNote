//
//  DictionaryLookupMenu.swift
//  MonkeyNote
//
//  Created by Nguyen Ngoc Khanh on 29/12/25.
//

#if os(macOS)
import SwiftUI
import AppKit
import AVFoundation
import NaturalLanguage
import CoreServices.DictionaryServices

// MARK: - Dictionary Lookup Menu (triggered by typing "word\")

class DictionaryLookupWindowController: NSObject, AVSpeechSynthesizerDelegate {
    private var window: NSPanel?
    private var backgroundView: NSView?
    private var scrollView: NSScrollView?
    private var textView: NSTextView?
    private var speakButton: NSButton?
    private var onDismiss: (() -> Void)?

    private var currentWord: String = ""
    private weak var parentWindow: NSWindow?
    private var menuOriginPoint: NSPoint = .zero
    private let speechSynthesizer = AVSpeechSynthesizer()
    private var isSpeakingWord: Bool = false

    private let menuWidth: CGFloat = 380
    private let menuMinHeight: CGFloat = 120
    private let menuMaxHeight: CGFloat = 400
    private let padding: CGFloat = 16
    private let speakButtonSize: CGFloat = 24

    override init() {
        super.init()
        speechSynthesizer.delegate = self
    }

    func show(at point: NSPoint, in parentWindow: NSWindow?, word: String, onDismiss: @escaping () -> Void) {
        self.onDismiss = onDismiss
        self.currentWord = word
        self.menuOriginPoint = point
        self.parentWindow = parentWindow

        createWindow(word: word)
    }

    private func createWindow(word: String) {
        stopSpeakingWord()

        // Remove existing window if any
        if let existingWindow = window {
            existingWindow.parent?.removeChildWindow(existingWindow)
            existingWindow.orderOut(nil)
        }

        // Get definition
        let definition = getDefinition(for: word)

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

        // Background view (blurred so text behind the popup isn't readable)
        let bgView = NSVisualEffectView(frame: NSRect(x: 0, y: 0, width: menuWidth, height: menuHeight))
        bgView.material = .hudWindow
        bgView.blendingMode = .behindWindow
        bgView.state = .active
        bgView.wantsLayer = true
        bgView.layer?.cornerRadius = 10
        bgView.layer?.masksToBounds = true
        bgView.layer?.borderWidth = 0.5
        bgView.layer?.borderColor = NSColor.white.withAlphaComponent(0.12).cgColor

        backgroundView = bgView

        // Setup scroll view with text
        setupScrollView(in: bgView, attributedContent: attributedContent, menuHeight: menuHeight)
        setupSpeakButton(in: bgView, menuHeight: menuHeight)

        panel.contentView = bgView
        self.window = panel

        parentWindow?.addChildWindow(panel, ordered: NSWindow.OrderingMode.above)
        panel.makeKeyAndOrderFront(self)
    }

    private func getDefinition(for word: String) -> String? {
        let trimmedWord = word.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedWord.isEmpty else { return nil }

        let nsString = trimmedWord as NSString
        let range = CFRange(location: 0, length: nsString.length)
        guard let definition = DCSCopyTextDefinition(nil, nsString, range) else {
            return nil
        }

        return definition.takeRetainedValue() as String
    }

    private func setupSpeakButton(in container: NSView, menuHeight: CGFloat) {
        let button = NSButton(frame: NSRect(
            x: menuWidth - padding - speakButtonSize,
            y: menuHeight - padding - speakButtonSize,
            width: speakButtonSize,
            height: speakButtonSize
        ))
        button.isBordered = false
        button.bezelStyle = .regularSquare
        button.wantsLayer = true
        button.layer?.cornerRadius = 6
        button.layer?.backgroundColor = NSColor.white.withAlphaComponent(0.08).cgColor
        button.contentTintColor = NSColor.white.withAlphaComponent(0.9)
        button.target = self
        button.action = #selector(toggleSpeakWord)
        button.toolTip = "Phat am"

        speakButton = button
        container.addSubview(button)
        updateSpeakButtonAppearance()
    }

    private func updateSpeakButtonAppearance() {
        guard let button = speakButton else { return }
        let symbolName = isSpeakingWord ? "stop.fill" : "speaker.wave.2.fill"
        button.image = NSImage(systemSymbolName: symbolName, accessibilityDescription: nil)
    }

    @objc private func toggleSpeakWord() {
        if isSpeakingWord {
            stopSpeakingWord()
            return
        }

        guard !currentWord.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }

        let utterance = AVSpeechUtterance(string: currentWord)
        let languageCode = preferredSpeechLanguageCode(for: currentWord)
        utterance.voice = bestVoice(for: languageCode)
        speechSynthesizer.speak(utterance)
        isSpeakingWord = true
        updateSpeakButtonAppearance()
    }

    private func stopSpeakingWord() {
        if speechSynthesizer.isSpeaking {
            speechSynthesizer.stopSpeaking(at: .immediate)
        }
        isSpeakingWord = false
        updateSpeakButtonAppearance()
    }

    private func bestVoice(for languageCode: String) -> AVSpeechSynthesisVoice? {
        let normalizedCode = normalizeLanguageCode(languageCode)

        if let exact = AVSpeechSynthesisVoice.speechVoices().first(where: {
            $0.language.lowercased().hasPrefix(normalizedCode.lowercased())
        }) {
            return exact
        }

        return AVSpeechSynthesisVoice(language: "en-US")
    }

    private func preferredSpeechLanguageCode(for word: String) -> String {
        let fallback = UserDefaults.standard.string(forKey: "note.dictionaryLanguage") ?? "en"
        let cleanedWord = word.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanedWord.isEmpty else { return fallback }

        let recognizer = NLLanguageRecognizer()
        recognizer.processString(cleanedWord)

        guard
            let detectedLanguage = recognizer.dominantLanguage,
            let confidence = recognizer.languageHypotheses(withMaximum: 1)[detectedLanguage],
            confidence >= 0.55
        else {
            return fallback
        }

        return detectedLanguage.rawValue
    }

    private func normalizeLanguageCode(_ languageCode: String) -> String {
        if languageCode == "zh-Hans" { return "zh" }
        if languageCode == "zh-Hant" { return "zh" }
        if let separatorIndex = languageCode.firstIndex(of: "_") {
            return String(languageCode[..<separatorIndex])
        }
        if let separatorIndex = languageCode.firstIndex(of: "-") {
            return String(languageCode[..<separatorIndex])
        }
        return languageCode
    }

    private func setupScrollView(in container: NSView, attributedContent: NSAttributedString, menuHeight: CGFloat) {
        // ScrollView stretches flush to the right edge so the scroller sits
        // at the popup border; the text keeps its 16pt right padding via textWidth.
        let scrollViewFrame = NSRect(
            x: padding,
            y: padding,
            width: menuWidth - padding,
            height: menuHeight - padding * 2
        )

        let scroll = NSScrollView(frame: scrollViewFrame)
        scroll.hasVerticalScroller = true
        scroll.hasHorizontalScroller = false
        scroll.autohidesScrollers = true
        scroll.scrollerStyle = .overlay
        scroll.borderType = .noBorder
        scroll.backgroundColor = .clear
        scroll.drawsBackground = false

        let textWidth = scroll.contentSize.width - padding
        let textViewFrame = NSRect(x: 0, y: 0, width: textWidth, height: scroll.contentSize.height)
        let text = NSTextView(frame: textViewFrame)
        text.isEditable = false
        text.isSelectable = true
        text.backgroundColor = .clear
        text.drawsBackground = false
        text.textContainerInset = NSSize(width: 0, height: 0)
        text.autoresizingMask = [.width]
        text.minSize = NSSize(width: 0, height: 0)
        text.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)

        text.textContainer?.widthTracksTextView = true
        text.textContainer?.containerSize = NSSize(width: textWidth, height: .greatestFiniteMagnitude)
        text.textContainer?.lineFragmentPadding = 0
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

    private func serifFont(size: CGFloat, bold: Bool = false, italic: Bool = false) -> NSFont {
        let name: String
        if bold && italic { name = "Georgia-BoldItalic" } else if bold { name = "Georgia-Bold" } else if italic { name = "Georgia-Italic" } else { name = "Georgia" }
        return NSFont(name: name, size: size) ?? NSFont.systemFont(ofSize: size, weight: bold ? .bold : .regular)
    }

    private func buildAttributedContent(word: String, definition: String?) -> NSAttributedString {
        let result = NSMutableAttributedString()

        // Word title (serif, bold) + pronunciation on same line
        let wordAttr = NSAttributedString(
            string: word.lowercased(),
            attributes: [
                .font: serifFont(size: 23, bold: true),
                .foregroundColor: NSColor.white,
            ]
        )
        result.append(wordAttr)

        guard let definition = definition else {
            result.append(NSAttributedString(string: "\n\n"))
            result.append(NSAttributedString(
                string: "No definition found",
                attributes: [
                    .font: NSFont.systemFont(ofSize: 13),
                    .foregroundColor: NSColor.white.withAlphaComponent(0.5),
                ]
            ))
            return result
        }

        let parsed = parseDefinition(definition, word: word)

        if !parsed.pronunciation.isEmpty {
            result.append(NSAttributedString(
                string: "  " + parsed.pronunciation,
                attributes: [
                    .font: serifFont(size: 14),
                    .foregroundColor: NSColor.white.withAlphaComponent(0.5),
                ]
            ))
        }
        result.append(NSAttributedString(string: "\n"))

        for part in parsed.parts {
            result.append(NSAttributedString(string: "\n"))
            // POS label e.g. "phó từ" — grey, indented
            if !part.partOfSpeech.isEmpty {
                result.append(NSAttributedString(
                    string: "  " + part.partOfSpeech + "\n",
                    attributes: [
                        .font: NSFont.systemFont(ofSize: 13),
                        .foregroundColor: NSColor.systemGray,
                    ]
                ))
            }
            for (index, def) in part.definitions.enumerated() {
                // Sense number (grey) + definition (serif bold white)
                let numAttr = NSAttributedString(
                    string: "    \(index + 1) ",
                    attributes: [
                        .font: NSFont.systemFont(ofSize: 13, weight: .semibold),
                        .foregroundColor: NSColor.white.withAlphaComponent(0.45),
                    ]
                )
                result.append(numAttr)
                result.append(NSAttributedString(
                    string: def.text + "\n",
                    attributes: [
                        .font: serifFont(size: 14, bold: true),
                        .foregroundColor: NSColor.white,
                    ]
                ))
                // Examples: EN line (grey italic) + VI line (white) below
                for example in def.examples {
                    result.append(NSAttributedString(
                        string: "      ▸ ",
                        attributes: [
                            .font: NSFont.systemFont(ofSize: 11),
                            .foregroundColor: NSColor.white.withAlphaComponent(0.4),
                        ]
                    ))
                    result.append(NSAttributedString(
                        string: example.en + "\n",
                        attributes: [
                            .font: serifFont(size: 13, italic: true),
                            .foregroundColor: NSColor.white.withAlphaComponent(0.6),
                        ]
                    ))
                    if let vi = example.vi, !vi.isEmpty {
                        result.append(NSAttributedString(
                            string: "          " + vi + "\n",
                            attributes: [
                                .font: serifFont(size: 13.5),
                                .foregroundColor: NSColor.white.withAlphaComponent(0.92),
                            ]
                        ))
                    }
                }
            }
        }

        // Synonyms / antonyms sections
        if let syn = parsed.synonyms, !syn.isEmpty {
            result.append(NSAttributedString(string: "\n"))
            result.append(NSAttributedString(
                string: "  TỪ ĐỒNG NGHĨA\n",
                attributes: [
                    .font: NSFont.systemFont(ofSize: 11, weight: .semibold),
                    .foregroundColor: NSColor.white.withAlphaComponent(0.45),
                ]
            ))
            result.append(NSAttributedString(
                string: "    " + syn + "\n",
                attributes: [
                    .font: serifFont(size: 13.5),
                    .foregroundColor: NSColor.white.withAlphaComponent(0.92),
                ]
            ))
        }
        if let ant = parsed.antonyms, !ant.isEmpty {
            result.append(NSAttributedString(string: "\n"))
            result.append(NSAttributedString(
                string: "  TỪ TRÁI NGHĨA\n",
                attributes: [
                    .font: NSFont.systemFont(ofSize: 11, weight: .semibold),
                    .foregroundColor: NSColor.white.withAlphaComponent(0.45),
                ]
            ))
            result.append(NSAttributedString(
                string: "    " + ant + "\n",
                attributes: [
                    .font: serifFont(size: 13.5),
                    .foregroundColor: NSColor.white.withAlphaComponent(0.92),
                ]
            ))
        }

        // Fallback: unstructured raw text
        if parsed.parts.isEmpty && parsed.synonyms == nil && parsed.antonyms == nil {
            result.append(NSAttributedString(string: "\n"))
            result.append(NSAttributedString(
                string: parsed.rawText,
                attributes: [
                    .font: serifFont(size: 13),
                    .foregroundColor: NSColor.white.withAlphaComponent(0.85),
                ]
            ))
        }

        return result
    }

    // MARK: - Parse Definition

    private struct ParsedDefinition {
        var pronunciation: String = ""
        var parts: [PartOfSpeech] = []
        var synonyms: String?
        var antonyms: String?
        var rawText: String = ""
    }

    private struct PartOfSpeech {
        var partOfSpeech: String
        var definitions: [Definition]
    }

    private struct Definition {
        var text: String
        var examples: [DictExample]
    }

    private struct DictExample {
        var en: String
        var vi: String?
    }

    /// Vietnamese diacritics used to detect where EN example ends / VI translation begins.
    private let vietnameseDiacritics = CharacterSet(charactersIn: "àáạảãâầấậẩẫăằắặẳẵèéẹẻẽêềếệểễìíịỉĩòóọỏõôồốộổỗơờớợởỡùúụủũưừứựửữỳýỵỷỹđÀÁẠẢÃÂẦẤẬẨẪĂẰẮẶẲẴÈÉẸẺẼÊỀẾỆỂỄÌÍỊỈĨÒÓỌỎÕÔỒỐỘỔỖƠỜỚỢỞỠÙÚỤỦŨƯỪỨỰỬỮỲÝỴỶỸĐ")

    /// Common VI function words (lowercased, punctuation stripped) — catches leading
    /// VI words without diacritics (e.g. "con", "toi") so the split doesn't start late.
    private let vietnameseFunctionWords: Set<String> = [
        "mot", "ngoi", "nha", "hom", "nay", "nguoi", "benh", "da", "hoi", "kha", "hon",
        "dua", "be", "the", "chat", "yeu", "ot", "con", "cai", "anh", "chi", "em",
        "toi", "ban", "ong", "ba", "no", "ho", "chung", "cua", "va", "voi", "cho",
        "la", "thi", "ma", "khong", "co", "duoc", "trong", "ngoai", "nay", "do",
        "nhung", "cac", "nhu", "de", "tu", "den", "rat", "lam", "nhieu", "it",
        "cung", "van", "lai", "len", "xuong", "ra", "vao", "o", "tai", "boi", "bi",
        "ve", "qua", "luc", "khi", "neu", "vi", "nen", "minh", "moi", "ai", "gi",
        "sao", "the", "nao", "dau", "noi", "viec", "lam", "di", "mot", "một", "ngôi",
        "nhà", "người", "đã", "hơi", "hơn", "đứa", "bé", "thể", "chất", "yếu", "ớt",
        "tôi", "bạn", "của", "và", "với", "không", "được", "những", "các", "đến",
        "rất", "nhiều", "lại", "ở", "về", "cô", "cháu", "ông", "bà", "anh", "ấy",
    ]

    /// Split "a slightly bigger house một ngôi nhà hơi lớn hơn" → (en, vi).
    private func splitExample(_ raw: String) -> DictExample {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return DictExample(en: "", vi: nil) }
        // No diacritics → pure English example (or untranslated).
        if text.rangeOfCharacter(from: vietnameseDiacritics) == nil {
            return DictExample(en: text, vi: nil)
        }
        let words = text.components(separatedBy: .whitespaces).filter { !$0.isEmpty }
        // Index of first word containing a VN diacritic.
        var firstVN = words.count
        for (i, w) in words.enumerated() where w.rangeOfCharacter(from: vietnameseDiacritics) != nil { firstVN = i; break }
        guard firstVN < words.count else { return DictExample(en: text, vi: nil) }
        // Walk back over ascii-only VI function words ("con", "toi", ...).
        var split = firstVN
        let punct = CharacterSet(charactersIn: ".,;:!?\"“”‘’'()[]")
        while split > 0 {
            let prev = words[split - 1].trimmingCharacters(in: punct).lowercased()
            if prev.rangeOfCharacter(from: vietnameseDiacritics) == nil
                && vietnameseFunctionWords.contains(prev) {
                split -= 1
            } else { break }
        }
        guard split > 0 && split < words.count else {
            // Degenerate: whole string is Vietnamese or no English part.
            if split == 0 { return DictExample(en: text, vi: nil) }
            return DictExample(en: text, vi: nil)
        }
        let en = words[..<split].joined(separator: " ")
        let vi = words[split...].joined(separator: " ")
        return DictExample(en: en, vi: vi)
    }

    private func cleanList(_ raw: String) -> String {
        // Split on newlines / semicolons / bullets, keep phrases like "to some extent" intact.
        let parts = raw
            .components(separatedBy: CharacterSet(charactersIn: "\n;•▸‣→▪"))
            .flatMap { $0.components(separatedBy: ",") }
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines)
                .trimmingCharacters(in: CharacterSet(charactersIn: "•-–—0123456789. "))
            }
            .filter { !$0.isEmpty && $0.count > 1 }
        // De-dupe while keeping order.
        var seen = Set<String>()
        var out: [String] = []
        for p in parts {
            let k = p.lowercased()
            if !seen.contains(k) { seen.insert(k); out.append(p) }
        }
        return out.joined(separator: ", ")
    }

    private func parseDefinition(_ definition: String, word: String) -> ParsedDefinition {
        var parsed = ParsedDefinition()
        parsed.rawText = definition

        // 1. Pronunciation: first |...| or /.../
        if let m = definition.range(of: "\\|[^|]+\\|", options: .regularExpression) {
            parsed.pronunciation = String(definition[m]).trimmingCharacters(in: .whitespaces)
        } else if let m = definition.range(of: "/[^/]+/", options: .regularExpression) {
            parsed.pronunciation = String(definition[m]).trimmingCharacters(in: .whitespaces)
        }

        var working = definition
        // 2. Strip leading headword + pronunciation.
        let wp = "^" + NSRegularExpression.escapedPattern(for: word) + "\\s*"
        if let re = try? NSRegularExpression(pattern: wp, options: .caseInsensitive) {
            working = re.stringByReplacingMatches(in: working, range: NSRange(working.startIndex..., in: working), withTemplate: "")
        }
        if !parsed.pronunciation.isEmpty {
            working = working.replacingOccurrences(of: parsed.pronunciation, with: "")
        }
        working = working.trimmingCharacters(in: .whitespacesAndNewlines)

        // 3. Cut off synonym / antonym tails (handles glued "vaguelytừ trái nghĩa").
        let synPat = "từ\\s+đồng\\s+nghĩa|đồng\\s+nghĩa|\\bsynonyms?\\b"
        let antPat = "từ\\s+trái\\s+nghĩa|trái\\s+nghĩa|\\bantonyms?\\b"
        var main = working
        var synRaw: String?
        var antRaw: String?
        if let re = try? NSRegularExpression(pattern: synPat, options: .caseInsensitive) {
            if let m = re.firstMatch(in: working, range: NSRange(working.startIndex..., in: working)),
               let r = Range(m.range, in: working) {
                main = String(working[..<r.lowerBound])
                let tail = String(working[r.upperBound...])
                if let re2 = try? NSRegularExpression(pattern: antPat, options: .caseInsensitive),
                   let m2 = re2.firstMatch(in: tail, range: NSRange(tail.startIndex..., in: tail)),
                   let r2 = Range(m2.range, in: tail) {
                    synRaw = String(tail[..<r2.lowerBound])
                    antRaw = String(tail[r2.upperBound...])
                } else {
                    synRaw = tail
                }
            }
        }
        if synRaw == nil, // no syn header — antonym may still exist alone
           let re2 = try? NSRegularExpression(pattern: antPat, options: .caseInsensitive),
           let m2 = re2.firstMatch(in: main, range: NSRange(main.startIndex..., in: main)),
           let r2 = Range(m2.range, in: main) {
            antRaw = String(main[r2.upperBound...])
            main = String(main[..<r2.lowerBound])
        }
        if let s = synRaw { parsed.synonyms = cleanList(s) }
        if let a = antRaw { parsed.antonyms = cleanList(a) }

        // 4. Split main body by Vietnamese POS headers.
        let posNames = [
            "ngoại động từ", "nội động từ", "trợ động từ",
            "danh từ", "động từ", "tính từ", "phó từ", "trạng từ",
            "đại từ", "giới từ", "liên từ", "thán từ", "mạo từ",
        ]
        let posPattern = "\\b(" + posNames.map(NSRegularExpression.escapedPattern(for:)) .joined(separator: "|") + ")\\b"
        var sections: [(pos: String, body: String)] = []
        if let re = try? NSRegularExpression(pattern: posPattern, options: .caseInsensitive) {
            let matches = re.matches(in: main, range: NSRange(main.startIndex..., in: main))
            if matches.isEmpty {
                sections = [("", main)]
            } else {
                // Text before first POS (usually empty) → attach to first section.
                for (i, m) in matches.enumerated() {
                    guard let mr = Range(m.range(at: 1), in: main) else { continue }
                    let pos = String(main[mr]).lowercased()
                    let bodyStart = m.range.upperBound
                    let bodyEnd = (i + 1 < matches.count) ? matches[i + 1].range.lowerBound : (main as NSString).length
                    let ns = main as NSString
                    let body = ns.substring(with: NSRange(location: bodyStart, length: bodyEnd - bodyStart))
                    sections.append((pos, body))
                }
            }
        } else {
            sections = [("", main)]
        }

        // 5. Within each section, split numbered senses.
        let exampleDelims = CharacterSet(charactersIn: "▸•‣→▪▹")
        for sec in sections {
            var senses: [Definition] = []
            let body = sec.body
            if let re = try? NSRegularExpression(pattern: "(?:^|\\s)(\\d+)\\s+", options: []) {
                let allMatches = re.matches(in: body, range: NSRange(body.startIndex..., in: body))
                // Only sequential numbers (1, 2, 3…) are sense boundaries —
                // skips in-content numbers like "19 hàng dọc".
                let nsBody = body as NSString
                var matches: [NSTextCheckingResult] = []
                var expected = 1
                for m in allMatches {
                    let numStr = nsBody.substring(with: m.range(at: 1))
                    if Int(numStr) == expected {
                        matches.append(m)
                        expected += 1
                    }
                }
                if matches.isEmpty {
                    senses = makeSenses(from: body, delims: exampleDelims)
                } else {
                    let ns = body as NSString
                    for (i, m) in matches.enumerated() {
                        // Sense text starts after the number.
                        let start = m.range.upperBound
                        let end = (i + 1 < matches.count)
                            ? matches[i + 1].range.location + 1 // include leading space in next match gap
                            : ns.length
                        let slice = ns.substring(with: NSRange(location: start, length: max(0, end - start)))
                            .trimmingCharacters(in: .whitespacesAndNewlines)
                        if slice.isEmpty { continue }
                        senses.append(contentsOf: makeSenses(from: slice, delims: exampleDelims))
                        if senses.count >= 12 { break }
                    }
                }
            } else {
                senses = makeSenses(from: body, delims: exampleDelims)
            }
            if !senses.isEmpty {
                parsed.parts.append(PartOfSpeech(partOfSpeech: sec.pos, definitions: senses))
            }
        }

        // 6. Fallback raw text (clean, keep newlines for readability, cap length).
        if parsed.parts.isEmpty && parsed.synonyms == nil && parsed.antonyms == nil {
            var raw = working.replacingOccurrences(of: "[ \\t]+", with: " ", options: .regularExpression)
            if raw.count > 600 {
                let idx = raw.index(raw.startIndex, offsetBy: 600)
                raw = String(raw[..<idx]) + "..."
            }
            parsed.rawText = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return parsed
    }

    /// Turn a body/slice into 1+ senses by splitting off ▸-examples.
    private func makeSenses(from text: String, delims: CharacterSet) -> [Definition] {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return [] }
        // Split keeping first chunk as definition, rest as examples.
        let chunks = t.components(separatedBy: delims)
        let head = chunks[0].trimmingCharacters(in: .whitespacesAndNewlines)
        guard !head.isEmpty else { return [] }
        var examples: [DictExample] = []
        for c in chunks.dropFirst() {
            let e = c.trimmingCharacters(in: .whitespacesAndNewlines)
            if e.count > 1 { examples.append(splitExample(e)) }
        }
        // ponytail: cap examples at 4 per sense, enough for popup.
        return [Definition(text: head, examples: Array(examples.prefix(4)))]
    }

    func updateWord(_ word: String) {
        currentWord = word
        if parentWindow != nil {
            createWindow(word: word)
        }
    }

    func dismiss() {
        stopSpeakingWord()
        if let window = self.window {
            window.parent?.removeChildWindow(window)
            window.orderOut(nil)
        }
        self.window = nil
        self.backgroundView = nil
        self.scrollView = nil
        self.textView = nil
        self.speakButton = nil
        onDismiss?()
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        isSpeakingWord = false
        updateSpeakButtonAppearance()
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        isSpeakingWord = false
        updateSpeakButtonAppearance()
    }

    var isVisible: Bool {
        window != nil
    }

    var currentLookupWord: String {
        currentWord
    }
}
#endif
