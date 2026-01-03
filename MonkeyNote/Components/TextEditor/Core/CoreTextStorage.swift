//
//  CoreTextStorage.swift
//  MonkeyNote
//
//  Custom text storage using Gap Buffer for efficient text editing operations.
//  Optimized for large documents with O(1) insert/delete at cursor position.
//

#if os(macOS)
import Foundation
import AppKit

/// A text position with affinity (forward or backward)
enum TextAffinity {
    case upstream   // Before the character (end of previous line for line breaks)
    case downstream // After the character (start of current position)
}

/// Represents a position in the text
struct TextPosition: Equatable, Comparable {
    let offset: Int
    var affinity: TextAffinity
    
    init(offset: Int, affinity: TextAffinity = .downstream) {
        self.offset = max(0, offset)
        self.affinity = affinity
    }
    
    static func < (lhs: TextPosition, rhs: TextPosition) -> Bool {
        lhs.offset < rhs.offset
    }
}

/// Represents a range of text
struct TextRange: Equatable {
    let start: TextPosition
    let end: TextPosition
    
    var nsRange: NSRange {
        let loc = min(start.offset, end.offset)
        let len = abs(end.offset - start.offset)
        return NSRange(location: loc, length: len)
    }
    
    var length: Int {
        abs(end.offset - start.offset)
    }
    
    var isEmpty: Bool {
        start.offset == end.offset
    }
    
    init(start: TextPosition, end: TextPosition) {
        self.start = start
        self.end = end
    }
    
    init(location: Int, length: Int) {
        self.start = TextPosition(offset: location)
        self.end = TextPosition(offset: location + length)
    }
    
    init(_ nsRange: NSRange) {
        self.start = TextPosition(offset: nsRange.location)
        self.end = TextPosition(offset: nsRange.location + nsRange.length)
    }
    
    func contains(_ position: Int) -> Bool {
        let loc = min(start.offset, end.offset)
        let maxLoc = max(start.offset, end.offset)
        return position >= loc && position < maxLoc
    }
    
    func intersects(_ other: TextRange) -> Bool {
        let selfStart = min(start.offset, end.offset)
        let selfEnd = max(start.offset, end.offset)
        let otherStart = min(other.start.offset, other.end.offset)
        let otherEnd = max(other.start.offset, other.end.offset)
        return selfStart < otherEnd && otherStart < selfEnd
    }
}

/// Efficient text storage using Gap Buffer algorithm
/// Provides O(1) amortized insert/delete at gap position, O(n) for moving gap
final class CoreTextStorage {
    
    // MARK: - Gap Buffer Storage
    
    /// Characters before the gap
    private var preGap: [Character] = []
    
    /// Characters after the gap (stored in reverse for efficient operations)
    private var postGap: [Character] = []
    
    /// Current gap position (cursor position for optimal editing)
    private(set) var gapPosition: Int = 0
    
    // MARK: - Attributed String Cache
    
    /// Cached attributed string (invalidated on edits)
    private var cachedAttributedString: NSMutableAttributedString?
    
    /// Default typing attributes
    var defaultAttributes: [NSAttributedString.Key: Any] = [
        .font: NSFont.monospacedSystemFont(ofSize: 14, weight: .regular),
        .foregroundColor: NSColor.textColor
    ]
    
    // MARK: - Line Cache
    
    /// Cached line break positions for fast line lookup
    private var lineBreakCache: [Int] = []
    private var isLineBreakCacheValid: Bool = false
    
    // MARK: - Undo Manager
    
    weak var undoManager: UndoManager?
    
    // MARK: - Delegate
    
    weak var delegate: CoreTextStorageDelegate?
    
    // MARK: - Initialization
    
    init(string: String = "") {
        preGap = Array(string)
        gapPosition = string.count
        invalidateCache()
    }
    
    // MARK: - Properties
    
    /// Total character count
    var length: Int {
        preGap.count + postGap.count
    }
    
    /// Check if storage is empty
    var isEmpty: Bool {
        length == 0
    }
    
    /// Get the full string
    var string: String {
        String(preGap) + String(postGap.reversed())
    }
    
    /// Get as NSString for compatibility
    var nsString: NSString {
        string as NSString
    }
    
    // MARK: - Gap Buffer Operations
    
    /// Move the gap to a specific position
    /// - Parameter position: Target position for the gap
    private func moveGap(to position: Int) {
        let targetPosition = min(max(0, position), length)
        
        if targetPosition == gapPosition {
            return
        }
        
        if targetPosition < gapPosition {
            // Move gap left: transfer characters from preGap to postGap
            let moveCount = gapPosition - targetPosition
            for _ in 0..<moveCount {
                if let char = preGap.popLast() {
                    postGap.append(char)
                }
            }
        } else {
            // Move gap right: transfer characters from postGap to preGap
            let moveCount = targetPosition - gapPosition
            for _ in 0..<moveCount {
                if let char = postGap.popLast() {
                    preGap.append(char)
                }
            }
        }
        
        gapPosition = targetPosition
    }
    
    // MARK: - Text Operations
    
    /// Insert text at a specific position
    /// - Parameters:
    ///   - text: Text to insert
    ///   - position: Position to insert at
    func insert(_ text: String, at position: Int) {
        guard !text.isEmpty else { return }
        
        let clampedPosition = min(max(0, position), length)
        
        // Register undo
        registerUndoForDelete(range: NSRange(location: clampedPosition, length: text.count))
        
        // Move gap to insertion point
        moveGap(to: clampedPosition)
        
        // Insert characters into preGap
        preGap.append(contentsOf: text)
        gapPosition += text.count
        
        // Invalidate caches
        invalidateCache()
        
        // Notify delegate
        delegate?.textStorage(self, didChangeInRange: NSRange(location: clampedPosition, length: 0),
                             changeInLength: text.count)
    }
    
    /// Delete text in a range
    /// - Parameter range: Range to delete
    func delete(range: NSRange) {
        guard range.length > 0 else { return }
        guard range.location >= 0 && range.location + range.length <= length else { return }
        
        // Get text for undo
        let deletedText = substring(with: range)
        registerUndoForInsert(text: deletedText, at: range.location)
        
        // Move gap to start of deletion range
        moveGap(to: range.location)
        
        // Remove characters by adjusting postGap
        let deleteCount = min(range.length, postGap.count)
        postGap.removeLast(deleteCount)
        
        // Invalidate caches
        invalidateCache()
        
        // Notify delegate
        delegate?.textStorage(self, didChangeInRange: range, changeInLength: -range.length)
    }
    
    /// Replace text in a range with new text
    /// - Parameters:
    ///   - range: Range to replace
    ///   - text: Replacement text
    func replace(range: NSRange, with text: String) {
        guard range.location >= 0 && range.location <= length else { return }
        
        let adjustedRange = NSRange(
            location: range.location,
            length: min(range.length, length - range.location)
        )
        
        // Get text for undo
        let replacedText = substring(with: adjustedRange)
        registerUndoForReplace(range: adjustedRange, with: text, originalText: replacedText)
        
        // Move gap to replacement position
        moveGap(to: adjustedRange.location)
        
        // Delete old content
        if adjustedRange.length > 0 {
            let deleteCount = min(adjustedRange.length, postGap.count)
            postGap.removeLast(deleteCount)
        }
        
        // Insert new content
        if !text.isEmpty {
            preGap.append(contentsOf: text)
            gapPosition += text.count
        }
        
        // Invalidate caches
        invalidateCache()
        
        // Notify delegate
        let delta = text.count - adjustedRange.length
        delegate?.textStorage(self, didChangeInRange: adjustedRange, changeInLength: delta)
    }
    
    /// Get character at a specific index
    /// - Parameter index: Character index
    /// - Returns: Character at index, or nil if out of bounds
    func character(at index: Int) -> Character? {
        guard index >= 0 && index < length else { return nil }
        
        if index < preGap.count {
            return preGap[index]
        } else {
            let postIndex = postGap.count - 1 - (index - preGap.count)
            return postGap[postIndex]
        }
    }
    
    /// Get substring for a range
    /// - Parameter range: Range of characters
    /// - Returns: Substring
    func substring(with range: NSRange) -> String {
        guard range.location >= 0 && range.location + range.length <= length else {
            return ""
        }
        
        var result = ""
        result.reserveCapacity(range.length)
        
        for i in range.location..<(range.location + range.length) {
            if let char = character(at: i) {
                result.append(char)
            }
        }
        
        return result
    }
    
    /// Set the entire string content
    /// - Parameter newString: New string content
    func setString(_ newString: String) {
        let oldLength = length
        
        preGap = Array(newString)
        postGap = []
        gapPosition = newString.count
        
        invalidateCache()
        
        delegate?.textStorage(self, didChangeInRange: NSRange(location: 0, length: oldLength),
                             changeInLength: newString.count - oldLength)
    }
    
    // MARK: - Attributed String
    
    /// Get attributed string representation
    var attributedString: NSAttributedString {
        if let cached = cachedAttributedString {
            return cached
        }
        
        let attrString = NSMutableAttributedString(string: string, attributes: defaultAttributes)
        cachedAttributedString = attrString
        return attrString
    }
    
    /// Get mutable attributed string for styling
    var mutableAttributedString: NSMutableAttributedString {
        if let cached = cachedAttributedString {
            return cached
        }
        
        let attrString = NSMutableAttributedString(string: string, attributes: defaultAttributes)
        cachedAttributedString = attrString
        return attrString
    }
    
    /// Apply attributes to a range
    /// - Parameters:
    ///   - attributes: Attributes to apply
    ///   - range: Range to apply to
    func addAttributes(_ attributes: [NSAttributedString.Key: Any], range: NSRange) {
        guard range.location >= 0 && range.location + range.length <= length else { return }
        mutableAttributedString.addAttributes(attributes, range: range)
    }
    
    /// Set attributes for a range (replacing existing)
    /// - Parameters:
    ///   - attributes: Attributes to set
    ///   - range: Range to set for
    func setAttributes(_ attributes: [NSAttributedString.Key: Any], range: NSRange) {
        guard range.location >= 0 && range.location + range.length <= length else { return }
        mutableAttributedString.setAttributes(attributes, range: range)
    }
    
    // MARK: - Line Operations
    
    /// Rebuild the line break cache
    private func rebuildLineBreakCache() {
        lineBreakCache = [0] // First line always starts at 0
        
        for (index, char) in string.enumerated() {
            if char == "\n" {
                lineBreakCache.append(index + 1)
            }
        }
        
        isLineBreakCacheValid = true
    }
    
    /// Get line count
    var lineCount: Int {
        if !isLineBreakCacheValid {
            rebuildLineBreakCache()
        }
        return lineBreakCache.count
    }
    
    /// Get line index for a character position
    /// - Parameter position: Character position
    /// - Returns: Line index (0-based)
    func lineIndex(for position: Int) -> Int {
        if !isLineBreakCacheValid {
            rebuildLineBreakCache()
        }
        
        // Binary search for the line containing position
        var low = 0
        var high = lineBreakCache.count - 1
        
        while low < high {
            let mid = (low + high + 1) / 2
            if lineBreakCache[mid] <= position {
                low = mid
            } else {
                high = mid - 1
            }
        }
        
        return low
    }
    
    /// Get character range for a line
    /// - Parameter lineIndex: Line index (0-based)
    /// - Returns: Character range for the line
    func lineRange(for lineIndex: Int) -> NSRange {
        if !isLineBreakCacheValid {
            rebuildLineBreakCache()
        }
        
        guard lineIndex >= 0 && lineIndex < lineBreakCache.count else {
            return NSRange(location: NSNotFound, length: 0)
        }
        
        let start = lineBreakCache[lineIndex]
        let end: Int
        
        if lineIndex + 1 < lineBreakCache.count {
            end = lineBreakCache[lineIndex + 1]
        } else {
            end = length
        }
        
        return NSRange(location: start, length: end - start)
    }
    
    /// Get the line range containing a position
    /// - Parameter position: Character position
    /// - Returns: Range of the line containing the position
    func lineRange(containing position: Int) -> NSRange {
        let line = lineIndex(for: position)
        return lineRange(for: line)
    }
    
    /// Get string content for a line
    /// - Parameter lineIndex: Line index (0-based)
    /// - Returns: Line content
    func lineContent(for lineIndex: Int) -> String {
        let range = lineRange(for: lineIndex)
        guard range.location != NSNotFound else { return "" }
        return substring(with: range)
    }
    
    // MARK: - Cache Management
    
    /// Invalidate all caches
    func invalidateCache() {
        cachedAttributedString = nil
        isLineBreakCacheValid = false
    }
    
    /// Invalidate cache for a specific range (for partial updates)
    func invalidateCache(in range: NSRange) {
        // For now, invalidate everything
        // Future optimization: only invalidate affected lines
        invalidateCache()
    }
    
    // MARK: - Undo Support
    
    private func registerUndoForDelete(range: NSRange) {
        undoManager?.registerUndo(withTarget: self) { [weak self] target in
            self?.delete(range: range)
        }
    }
    
    private func registerUndoForInsert(text: String, at position: Int) {
        undoManager?.registerUndo(withTarget: self) { [weak self] target in
            self?.insert(text, at: position)
        }
    }
    
    private func registerUndoForReplace(range: NSRange, with newText: String, originalText: String) {
        let newRange = NSRange(location: range.location, length: newText.count)
        undoManager?.registerUndo(withTarget: self) { [weak self] target in
            self?.replace(range: newRange, with: originalText)
        }
    }
}

// MARK: - Delegate Protocol

protocol CoreTextStorageDelegate: AnyObject {
    /// Called when text content changes
    func textStorage(_ storage: CoreTextStorage, didChangeInRange range: NSRange, changeInLength delta: Int)
}

// MARK: - Debug Extensions

#if DEBUG
extension CoreTextStorage {
    /// Debug description showing gap buffer state
    var debugDescription: String {
        """
        CoreTextStorage:
          Length: \(length)
          Gap Position: \(gapPosition)
          PreGap: \(preGap.count) chars
          PostGap: \(postGap.count) chars
          Lines: \(lineCount)
          Content: "\(string.prefix(100))\(length > 100 ? "..." : "")"
        """
    }
}
#endif

#endif
