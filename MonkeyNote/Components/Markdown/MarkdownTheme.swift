//
//  MarkdownTheme.swift
//  MonkeyNote
//
//  Created by Claude on 04/01/26.
//

import AppKit

/// Theme configuration for markdown rendering
struct MarkdownTheme {
    
    // MARK: - Bold Style (Yellow color as requested)
    var boldColor: NSColor
    var boldFont: NSFont?  // nil means use base font with bold trait
    
    // MARK: - Italic Style
    var italicColor: NSColor?  // nil means use default text color
    var italicFont: NSFont?
    
    // MARK: - Code Style
    var codeColor: NSColor
    var codeBackgroundColor: NSColor
    var codeFont: NSFont?  // Monospace font
    
    // MARK: - Strikethrough Style
    var strikethroughColor: NSColor?
    
    // MARK: - Heading Styles
    var heading1Color: NSColor?
    var heading1Font: NSFont?
    var heading2Color: NSColor?
    var heading2Font: NSFont?
    var heading3Color: NSColor?
    var heading3Font: NSFont?
    
    // MARK: - Syntax Marker Style (when visible)
    var syntaxMarkerColor: NSColor
    var syntaxMarkerFont: NSFont?
    
    // MARK: - Base Style
    var baseFont: NSFont
    var baseColor: NSColor
    
    // MARK: - Default Themes
    
    /// Light mode theme
    static func light(baseFont: NSFont) -> MarkdownTheme {
        return MarkdownTheme(
            // Bold - Yellow color (no bold weight, just color)
            boldColor: NSColor(red: 0.9, green: 0.7, blue: 0.0, alpha: 1.0),  // Golden yellow
            boldFont: nil,
            
            // Italic
            italicColor: nil,
            italicFont: nil,
            
            // Code
            codeColor: NSColor(red: 0.8, green: 0.2, blue: 0.3, alpha: 1.0),
            codeBackgroundColor: NSColor(white: 0.95, alpha: 1.0),
            codeFont: NSFont.monospacedSystemFont(ofSize: baseFont.pointSize * 0.9, weight: .regular),
            
            // Strikethrough
            strikethroughColor: NSColor.gray,
            
            // Headings
            heading1Color: NSColor.labelColor,
            heading1Font: NSFont.systemFont(ofSize: baseFont.pointSize * 1.8, weight: .bold),
            heading2Color: NSColor.labelColor,
            heading2Font: NSFont.systemFont(ofSize: baseFont.pointSize * 1.5, weight: .bold),
            heading3Color: NSColor.labelColor,
            heading3Font: NSFont.systemFont(ofSize: baseFont.pointSize * 1.25, weight: .semibold),
            
            // Syntax markers (**, __, etc.) - dimmed when visible
            syntaxMarkerColor: NSColor.tertiaryLabelColor,
            syntaxMarkerFont: nil,
            
            // Base
            baseFont: baseFont,
            baseColor: NSColor.labelColor
        )
    }
    
    /// Dark mode theme
    static func dark(baseFont: NSFont) -> MarkdownTheme {
        return MarkdownTheme(
            // Bold - Bright yellow for dark mode
            boldColor: NSColor(red: 1.0, green: 0.85, blue: 0.2, alpha: 1.0),  // Bright yellow
            boldFont: nil,
            
            // Italic
            italicColor: nil,
            italicFont: nil,
            
            // Code
            codeColor: NSColor(red: 0.98, green: 0.4, blue: 0.4, alpha: 1.0),
            codeBackgroundColor: NSColor(white: 0.15, alpha: 1.0),
            codeFont: NSFont.monospacedSystemFont(ofSize: baseFont.pointSize * 0.9, weight: .regular),
            
            // Strikethrough
            strikethroughColor: NSColor.gray,
            
            // Headings
            heading1Color: NSColor.labelColor,
            heading1Font: NSFont.systemFont(ofSize: baseFont.pointSize * 1.8, weight: .bold),
            heading2Color: NSColor.labelColor,
            heading2Font: NSFont.systemFont(ofSize: baseFont.pointSize * 1.5, weight: .bold),
            heading3Color: NSColor.labelColor,
            heading3Font: NSFont.systemFont(ofSize: baseFont.pointSize * 1.25, weight: .semibold),
            
            // Syntax markers - dimmed
            syntaxMarkerColor: NSColor.tertiaryLabelColor,
            syntaxMarkerFont: nil,
            
            // Base
            baseFont: baseFont,
            baseColor: NSColor.labelColor
        )
    }
    
    /// Get theme based on appearance
    static func forAppearance(isDark: Bool, baseFont: NSFont) -> MarkdownTheme {
        return isDark ? dark(baseFont: baseFont) : light(baseFont: baseFont)
    }
}
