//
//  MarkdownParser.swift
//  MonkeyNote
//
//  Created by Claude on 04/01/26.
//

import Foundation
import SwiftTreeSitter
import TreeSitterMarkdown

// External C function from TreeSitterMarkdownInline
// Declared here to avoid "Cannot find in scope" error while still using the linked library
@_silgen_name("tree_sitter_markdown_inline")
func tree_sitter_markdown_inline() -> OpaquePointer

/// Represents a parsed markdown element with its range and type
struct MarkdownElement {
    enum ElementType {
        case bold           // **text** or __text__
        case italic         // *text* or _text_
        case boldItalic     // ***text*** or ___text___
        case code           // `code`
        case codeBlock      // ```code```
        case heading1       // # heading
        case heading2       // ## heading
        case heading3       // ### heading
        case heading4       // #### heading
        case heading5       // ##### heading
        case heading6       // ###### heading
        case strikethrough  // ~~text~~
        case highlight      // ==text==
        case link           // [text](url)
        case image          // ![alt](url)
        case blockquote     // > text
        case listItem       // - item or * item or 1. item
    }
    
    let type: ElementType
    let range: NSRange           // Full range including syntax markers
    let contentRange: NSRange    // Range of actual content (without syntax)
    let syntaxRanges: [NSRange]  // Ranges of syntax markers (**, __, etc.)
}

/// Parses markdown text using Tree-sitter and returns structured elements
class MarkdownParser {
    private var parser: Parser?
    private var tree: MutableTree?
    private var language: Language?
    
    init() {
        setupParser()
    }
    
    private func setupParser() {
        do {
            // Get the markdown inline language from TreeSitterMarkdown
            let markdownInline = Language(language: tree_sitter_markdown_inline())
            self.language = markdownInline
            
            // Create parser
            let parser = Parser()
            try parser.setLanguage(markdownInline)
            self.parser = parser
        } catch {
            print("MarkdownParser: Failed to setup parser: \(error)")
        }
    }
    
    /// Parse the given text and return markdown elements
    func parse(_ text: String) -> [MarkdownElement] {
        guard let parser = parser else {
            print("MarkdownParser: Parser not initialized")
            return []
        }
        
        // Parse the text
        tree = parser.parse(text)
        
        guard let tree = tree, let rootNode = tree.rootNode else {
            print("MarkdownParser: Failed to parse text")
            return []
        }
        
        var elements: [MarkdownElement] = []
        
        // Traverse the tree and extract elements
        traverseNode(rootNode, in: text, elements: &elements)
        
        return elements
    }
    
    /// Incrementally update the parse tree when text changes
    func update(_ text: String, editedRange: NSRange, replacementLength: Int) -> [MarkdownElement] {
        guard let parser = parser else {
            return parse(text)
        }
        
        // For now, do a full reparse (incremental can be added later for performance)
        // Tree-sitter supports incremental parsing but requires careful edit tracking
        tree = parser.parse(text)
        
        guard let tree = tree, let rootNode = tree.rootNode else {
            return []
        }
        
        var elements: [MarkdownElement] = []
        traverseNode(rootNode, in: text, elements: &elements)
        
        return elements
    }
    
    /// Recursively traverse the syntax tree
    private func traverseNode(_ node: Node, in text: String, elements: inout [MarkdownElement]) {
        let nodeType = node.nodeType ?? ""
        
        // Process this node if it's a markdown element we care about
        if let element = createElement(from: node, nodeType: nodeType, in: text) {
            elements.append(element)
        }
        
        // Traverse children
        for i in 0..<node.childCount {
            if let child = node.child(at: i) {
                traverseNode(child, in: text, elements: &elements)
            }
        }
    }
    
    /// Create a MarkdownElement from a tree-sitter node
    private func createElement(from node: Node, nodeType: String, in text: String) -> MarkdownElement? {
        // Use node.range which is already UTF-16 based NSRange
        let range = node.range
        
        switch nodeType {
        case "strong_emphasis", "strong":
            // Bold: **text** or __text__
            return createBoldElement(node: node, range: range, in: text)
            
        case "emphasis":
            // Italic: *text* or _text_
            return createItalicElement(node: node, range: range, in: text)
            
        case "code_span":
            // Inline code: `code`
            return createCodeElement(node: node, range: range, in: text)
            
        case "strikethrough":
            // Strikethrough: ~~text~~
            return createStrikethroughElement(node: node, range: range, in: text)
            
        default:
            return nil
        }
    }
    
    /// Create a bold element with proper syntax ranges
    private func createBoldElement(node: Node, range: NSRange, in text: String) -> MarkdownElement? {
        // Bold uses ** or __ as delimiters (2 chars each side)
        guard range.length >= 4 else { return nil }
        
        let syntaxLength = 2  // ** or __
        
        let openingSyntax = NSRange(location: range.location, length: syntaxLength)
        let closingSyntax = NSRange(location: range.location + range.length - syntaxLength, length: syntaxLength)
        let contentRange = NSRange(
            location: range.location + syntaxLength,
            length: range.length - (syntaxLength * 2)
        )
        
        return MarkdownElement(
            type: .bold,
            range: range,
            contentRange: contentRange,
            syntaxRanges: [openingSyntax, closingSyntax]
        )
    }
    
    /// Create an italic element with proper syntax ranges
    private func createItalicElement(node: Node, range: NSRange, in text: String) -> MarkdownElement? {
        guard range.length >= 2 else { return nil }
        
        let syntaxLength = 1  // * or _
        
        let openingSyntax = NSRange(location: range.location, length: syntaxLength)
        let closingSyntax = NSRange(location: range.location + range.length - syntaxLength, length: syntaxLength)
        let contentRange = NSRange(
            location: range.location + syntaxLength,
            length: range.length - (syntaxLength * 2)
        )
        
        return MarkdownElement(
            type: .italic,
            range: range,
            contentRange: contentRange,
            syntaxRanges: [openingSyntax, closingSyntax]
        )
    }
    
    /// Create an inline code element
    private func createCodeElement(node: Node, range: NSRange, in text: String) -> MarkdownElement? {
        guard range.length >= 2 else { return nil }
        
        let syntaxLength = 1  // `
        
        let openingSyntax = NSRange(location: range.location, length: syntaxLength)
        let closingSyntax = NSRange(location: range.location + range.length - syntaxLength, length: syntaxLength)
        let contentRange = NSRange(
            location: range.location + syntaxLength,
            length: range.length - (syntaxLength * 2)
        )
        
        return MarkdownElement(
            type: .code,
            range: range,
            contentRange: contentRange,
            syntaxRanges: [openingSyntax, closingSyntax]
        )
    }
    
    /// Create a strikethrough element
    private func createStrikethroughElement(node: Node, range: NSRange, in text: String) -> MarkdownElement? {
        guard range.length >= 4 else { return nil }
        
        let syntaxLength = 2  // ~~
        
        let openingSyntax = NSRange(location: range.location, length: syntaxLength)
        let closingSyntax = NSRange(location: range.location + range.length - syntaxLength, length: syntaxLength)
        let contentRange = NSRange(
            location: range.location + syntaxLength,
            length: range.length - (syntaxLength * 2)
        )
        
        return MarkdownElement(
            type: .strikethrough,
            range: range,
            contentRange: contentRange,
            syntaxRanges: [openingSyntax, closingSyntax]
        )
    }
}
