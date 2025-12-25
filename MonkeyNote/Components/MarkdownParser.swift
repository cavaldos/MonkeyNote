//
//  MarkdownParser.swift
//  MonkeyNote
//
//  Created on 26/12/25.
//

#if os(macOS)
import AppKit

// MARK: - Markdown Style
enum MarkdownStyle {
    case bold           // **text** or __text__
    case italic         // *text* or _text_
    case boldItalic     // ***text*** or ___text___
    case strikethrough  // ~~text~~
    case highlight      // ==text==
    case inlineCode     // `code`
    case heading1       // # heading
    case heading2       // ## heading
    case heading3       // ### heading
    case link           // [text](url)
    case image          // ![alt](url)
    case numberedList   // 1. 2. 3. etc.
    case bulletList     // • bullet
}

// MARK: - Markdown Match
struct MarkdownMatch {
    let range: NSRange           // Full range including syntax
    let contentRange: NSRange    // Range of actual content (without syntax)
    let style: MarkdownStyle
    let syntaxRanges: [NSRange]  // Ranges of syntax characters to hide
    let url: String?             // For links
}

// MARK: - Markdown Parser
class MarkdownParser {
    static let shared = MarkdownParser()
    
    private var patterns: [(regex: NSRegularExpression, style: MarkdownStyle, syntaxLengths: (prefix: Int, suffix: Int))] = []
    
    private init() {
        setupPatterns()
    }
    
    private func setupPatterns() {
        // Order matters - more specific patterns first
        let patternDefinitions: [(pattern: String, style: MarkdownStyle, prefix: Int, suffix: Int)] = [
            // Headings (must be at start of line)
            ("^### (.+)$", .heading3, 4, 0),
            ("^## (.+)$", .heading2, 3, 0),
            ("^# (.+)$", .heading1, 2, 0),
            
            // Numbered list - only match the number and dot at start of line (e.g. "1.", "12.")
            // Uses lookahead to ensure space follows but doesn't include it in match
            ("^(\\d+\\.)", .numberedList, 0, 0),
            
            // Bullet list - match bullet at start of line (only the bullet, not the space)
            ("^(•)", .bulletList, 0, 0),
            
            // Bold + Italic (must come before bold and italic)
            ("\\*\\*\\*([^*]+)\\*\\*\\*", .boldItalic, 3, 3),
            ("___([^_]+)___", .boldItalic, 3, 3),
            
            // Bold - match ** or __ with content that doesn't contain the delimiter
            ("\\*\\*([^*]+)\\*\\*", .bold, 2, 2),
            ("__([^_]+)__", .bold, 2, 2),
            
            // Strikethrough
            ("~~([^~]+)~~", .strikethrough, 2, 2),
            
            // Highlight
            ("==([^=]+)==", .highlight, 2, 2),
            
            // Inline code
            ("`([^`]+)`", .inlineCode, 1, 1),
            
            // Images ![alt](url) - must come before links
            ("!\\[([^\\]]+)\\]\\(([^)]+)\\)", .image, 0, 0),
            
            // Links [text](url)
            ("\\[([^\\]]+)\\]\\(([^)]+)\\)", .link, 0, 0),
            
            // Italic - simpler pattern, processed last to avoid conflicts
            // Using word boundary to avoid matching inside URLs or other patterns
            ("\\*([^*\\n]+)\\*", .italic, 1, 1),
            ("(?<![\\w])_([^_\\n]+)_(?![\\w])", .italic, 1, 1),
        ]
        
        for definition in patternDefinitions {
            do {
                let options: NSRegularExpression.Options
                switch definition.style {
                case .heading1, .heading2, .heading3, .numberedList, .bulletList:
                    options = [.anchorsMatchLines]
                default:
                    options = []
                }
                let regex = try NSRegularExpression(pattern: definition.pattern, options: options)
                patterns.append((regex, definition.style, (definition.prefix, definition.suffix)))
            } catch {
                print("Failed to create regex for pattern: \(definition.pattern), error: \(error)")
            }
        }
    }
    
    // MARK: - Parse Text
    func parse(_ text: String) -> [MarkdownMatch] {
        var matches: [MarkdownMatch] = []
        let nsText = text as NSString
        let fullRange = NSRange(location: 0, length: nsText.length)
        
        for (regex, style, syntaxLengths) in patterns {
            let regexMatches = regex.matches(in: text, options: [], range: fullRange)
            
            for match in regexMatches {
                guard match.range.location != NSNotFound else { continue }
                
                // Check if this range overlaps with existing matches
                let overlaps = matches.contains { existing in
                    NSIntersectionRange(existing.range, match.range).length > 0
                }
                
                if overlaps { continue }
                
                let markdownMatch: MarkdownMatch
                
                switch style {
                case .link, .image:
                    markdownMatch = parseLinkOrImage(match: match, style: style, in: nsText)
                    
                case .heading1, .heading2, .heading3:
                    markdownMatch = parseHeading(match: match, style: style, syntaxLengths: syntaxLengths, in: nsText)
                    
                case .numberedList, .bulletList:
                    markdownMatch = parseListMarker(match: match, style: style, in: nsText)
                    
                default:
                    markdownMatch = parseInlineStyle(match: match, style: style, syntaxLengths: syntaxLengths, in: nsText)
                }
                
                matches.append(markdownMatch)
            }
        }
        
        // Sort by location
        matches.sort { $0.range.location < $1.range.location }
        
        return matches
    }
    
    private func parseInlineStyle(match: NSTextCheckingResult, style: MarkdownStyle, syntaxLengths: (prefix: Int, suffix: Int), in text: NSString) -> MarkdownMatch {
        let fullRange = match.range
        let prefixRange = NSRange(location: fullRange.location, length: syntaxLengths.prefix)
        let suffixRange = NSRange(location: fullRange.location + fullRange.length - syntaxLengths.suffix, length: syntaxLengths.suffix)
        
        let contentRange = NSRange(
            location: fullRange.location + syntaxLengths.prefix,
            length: fullRange.length - syntaxLengths.prefix - syntaxLengths.suffix
        )
        
        return MarkdownMatch(
            range: fullRange,
            contentRange: contentRange,
            style: style,
            syntaxRanges: [prefixRange, suffixRange],
            url: nil
        )
    }
    
    private func parseHeading(match: NSTextCheckingResult, style: MarkdownStyle, syntaxLengths: (prefix: Int, suffix: Int), in text: NSString) -> MarkdownMatch {
        let fullRange = match.range
        let prefixRange = NSRange(location: fullRange.location, length: syntaxLengths.prefix)
        
        let contentRange = NSRange(
            location: fullRange.location + syntaxLengths.prefix,
            length: fullRange.length - syntaxLengths.prefix
        )
        
        return MarkdownMatch(
            range: fullRange,
            contentRange: contentRange,
            style: style,
            syntaxRanges: [prefixRange],
            url: nil
        )
    }
    
    private func parseLinkOrImage(match: NSTextCheckingResult, style: MarkdownStyle, in text: NSString) -> MarkdownMatch {
        let fullRange = match.range
        
        // For [text](url) pattern:
        // Group 1 = text, Group 2 = url
        let textRange = match.range(at: 1)
        let urlRange = match.range(at: 2)
        
        let url = urlRange.location != NSNotFound ? text.substring(with: urlRange) : nil
        
        // Syntax ranges: [ ] ( ) and the url
        var syntaxRanges: [NSRange] = []
        
        // Opening bracket [ or ![
        let openBracketLength = style == .image ? 2 : 1
        syntaxRanges.append(NSRange(location: fullRange.location, length: openBracketLength))
        
        // Closing bracket and opening paren ](
        let closingBracketLoc = textRange.location + textRange.length
        syntaxRanges.append(NSRange(location: closingBracketLoc, length: 2))
        
        // URL and closing paren
        if urlRange.location != NSNotFound {
            syntaxRanges.append(NSRange(location: urlRange.location, length: urlRange.length + 1))
        }
        
        return MarkdownMatch(
            range: fullRange,
            contentRange: textRange,
            style: style,
            syntaxRanges: syntaxRanges,
            url: url
        )
    }
    
    private func parseListMarker(match: NSTextCheckingResult, style: MarkdownStyle, in text: NSString) -> MarkdownMatch {
        let fullRange = match.range
        
        // For numbered list "1. " or bullet "• ", the whole match is the marker
        // contentRange is the same as fullRange (we want to color the whole marker)
        // No syntax ranges to hide
        
        return MarkdownMatch(
            range: fullRange,
            contentRange: fullRange,
            style: style,
            syntaxRanges: [],  // Don't hide anything
            url: nil
        )
    }
}

// MARK: - Style Attributes
extension MarkdownParser {
    func attributes(for style: MarkdownStyle, baseFont: NSFont) -> [NSAttributedString.Key: Any] {
        var attributes: [NSAttributedString.Key: Any] = [:]
        
        switch style {
        case .bold:
            // Try to get bold font, fallback to system bold if not available
            let boldFont = getBoldFont(from: baseFont)
            attributes[.font] = boldFont
            // Add orange/yellow color to make bold more visible
            attributes[.foregroundColor] = NSColor(red: 1.0, green: 0.8, blue: 0.2, alpha: 1.0) // Golden yellow
            
        case .italic:
            // Try to get italic font
            let italicFont = getItalicFont(from: baseFont)
            attributes[.font] = italicFont
            // Add a subtle color for italic
            attributes[.foregroundColor] = NSColor(red: 0.6, green: 0.8, blue: 1.0, alpha: 1.0) // Light blue
            
        case .boldItalic:
            let boldItalicFont = getBoldItalicFont(from: baseFont)
            attributes[.font] = boldItalicFont
            // Orange color for bold italic
            attributes[.foregroundColor] = NSColor(red: 1.0, green: 0.6, blue: 0.2, alpha: 1.0) // Orange
            
        case .strikethrough:
            attributes[.strikethroughStyle] = NSUnderlineStyle.single.rawValue
            attributes[.strikethroughColor] = NSColor.systemRed
            attributes[.foregroundColor] = NSColor.gray
            
        case .highlight:
            attributes[.backgroundColor] = NSColor.yellow.withAlphaComponent(0.5)
            attributes[.foregroundColor] = NSColor.black
            
        case .inlineCode:
            let codeFont = NSFont.monospacedSystemFont(ofSize: baseFont.pointSize * 0.85, weight: .medium)
            attributes[.font] = codeFont
            // Use custom key for rounded background (handled by ThickCursorLayoutManager)
            let roundedBackgroundKey = NSAttributedString.Key("roundedBackgroundColor")
            attributes[roundedBackgroundKey] = NSColor(red: 0.2, green: 0.2, blue: 0.22, alpha: 1.0) // Dark background
            attributes[.foregroundColor] = NSColor(red: 0.95, green: 0.45, blue: 0.45, alpha: 1.0) // Coral/red color
            
        case .heading1:
            let size = baseFont.pointSize * 1.6
            attributes[.font] = NSFont.systemFont(ofSize: size, weight: .bold)
            // Brown color for all headings
            attributes[.foregroundColor] = NSColor(red: 0.6, green: 0.4, blue: 0.2, alpha: 1.0)
            
        case .heading2:
            let size = baseFont.pointSize * 1.4
            attributes[.font] = NSFont.systemFont(ofSize: size, weight: .bold)
            // Brown color for all headings
            attributes[.foregroundColor] = NSColor(red: 0.6, green: 0.4, blue: 0.2, alpha: 1.0)
            
        case .heading3:
            let size = baseFont.pointSize * 1.2
            attributes[.font] = NSFont.systemFont(ofSize: size, weight: .semibold)
            // Brown color for all headings
            attributes[.foregroundColor] = NSColor(red: 0.6, green: 0.4, blue: 0.2, alpha: 1.0)
            
        case .link:
            attributes[.foregroundColor] = NSColor.systemBlue
            attributes[.underlineStyle] = NSUnderlineStyle.single.rawValue
            
        case .image:
            attributes[.foregroundColor] = NSColor.systemPurple
            attributes[.underlineStyle] = NSUnderlineStyle.single.rawValue
            
        case .numberedList:
            // Purple color for numbered list markers (1. 2. 3. etc.)
            attributes[.foregroundColor] = NSColor(red: 0.7, green: 0.4, blue: 0.9, alpha: 1.0) // Purple
            
        case .bulletList:
            // Purple color for bullet markers (•)
            attributes[.foregroundColor] = NSColor(red: 0.7, green: 0.4, blue: 0.9, alpha: 1.0) // Purple
        }
        
        return attributes
    }
    
    // MARK: - Font Helpers
    
    private func getBoldFont(from baseFont: NSFont) -> NSFont {
        // Try NSFontManager first
        let converted = NSFontManager.shared.convert(baseFont, toHaveTrait: .boldFontMask)
        if converted != baseFont {
            return converted
        }
        
        // Fallback: try to get bold variant by name
        if let fontFamily = baseFont.familyName,
           let boldFont = NSFont(name: "\(fontFamily)-Bold", size: baseFont.pointSize) {
            return boldFont
        }
        
        // Final fallback: use system bold font
        return NSFont.boldSystemFont(ofSize: baseFont.pointSize)
    }
    
    private func getItalicFont(from baseFont: NSFont) -> NSFont {
        // Try NSFontManager first
        let converted = NSFontManager.shared.convert(baseFont, toHaveTrait: .italicFontMask)
        if converted != baseFont {
            return converted
        }
        
        // Fallback: try to get italic variant by name
        if let fontFamily = baseFont.familyName,
           let italicFont = NSFont(name: "\(fontFamily)-Italic", size: baseFont.pointSize) {
            return italicFont
        }
        
        // Final fallback: try using font descriptor with italic trait
        let italicDescriptor = baseFont.fontDescriptor.withSymbolicTraits(.italic)
        if let italicFont = NSFont(descriptor: italicDescriptor, size: baseFont.pointSize) {
            return italicFont
        }
        
        return baseFont
    }
    
    private func getBoldItalicFont(from baseFont: NSFont) -> NSFont {
        // Try to get both traits
        var font = NSFontManager.shared.convert(baseFont, toHaveTrait: .boldFontMask)
        font = NSFontManager.shared.convert(font, toHaveTrait: .italicFontMask)
        
        if font != baseFont {
            return font
        }
        
        // Fallback to bold system font
        return NSFont.boldSystemFont(ofSize: baseFont.pointSize)
    }
    
    // Attributes for hidden syntax characters
    var hiddenSyntaxAttributes: [NSAttributedString.Key: Any] {
        return [
            .font: NSFont.systemFont(ofSize: 0.01),
            .foregroundColor: NSColor.clear
        ]
    }
    
    // Attributes for visible syntax characters (when cursor is nearby)
    func visibleSyntaxAttributes(baseFont: NSFont) -> [NSAttributedString.Key: Any] {
        return [
            .font: baseFont,
            .foregroundColor: NSColor.gray.withAlphaComponent(0.5)
        ]
    }
}
#endif
