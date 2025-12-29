//
//  DictionaryService.swift
//  MonkeyNote
//
//  Created by Nguyen Ngoc Khanh on 29/12/25.
//

#if os(macOS)
import Foundation
import AppKit
import CoreServices.DictionaryServices

/// Service for interacting with macOS system dictionary via NSSpellChecker
class DictionaryService {
    static let shared = DictionaryService()
    
    private let spellChecker = NSSpellChecker.shared
    
    // Cache for completions to avoid repeated lookups
    private var completionCache: [String: [String]] = [:]
    private var definitionCache: [String: String] = [:]
    private let maxCacheSize = 100
    
    private init() {}
    
    // MARK: - Available Languages
    
    /// Get list of available languages for spell checking
    var availableLanguages: [String] {
        return spellChecker.availableLanguages
    }
    
    /// Common language options with display names
    static let commonLanguages: [(code: String, name: String)] = [
        ("en", "English"),
        ("en_US", "English (US)"),
        ("en_GB", "English (UK)"),
        ("vi", "Vietnamese"),
        ("fr", "French"),
        ("de", "German"),
        ("es", "Spanish"),
        ("it", "Italian"),
        ("pt", "Portuguese"),
        ("ja", "Japanese"),
        ("ko", "Korean"),
        ("zh-Hans", "Chinese (Simplified)"),
        ("zh-Hant", "Chinese (Traditional)")
    ]
    
    // MARK: - Dictionary Lookup
    
    /// Get the definition of a word from the system dictionary
    /// - Parameter word: The word to look up
    /// - Returns: The definition text, or nil if not found
    func getDefinition(for word: String) -> String? {
        let trimmedWord = word.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedWord.isEmpty else { return nil }
        
        let cacheKey = trimmedWord.lowercased()
        
        // Check cache first
        if let cached = definitionCache[cacheKey] {
            return cached
        }
        
        // Use DCSCopyTextDefinition (public API)
        let nsString = trimmedWord as NSString
        let range = CFRange(location: 0, length: nsString.length)
        
        guard let definition = DCSCopyTextDefinition(nil, nsString, range) else {
            return nil
        }
        
        let result = definition.takeRetainedValue() as String
        
        // Cache the result
        if definitionCache.count >= maxCacheSize {
            if let firstKey = definitionCache.keys.first {
                definitionCache.removeValue(forKey: firstKey)
            }
        }
        definitionCache[cacheKey] = result
        
        return result
    }
    
    /// Check if a word has a definition in the dictionary
    /// - Parameter word: The word to check
    /// - Returns: true if the word has a definition
    func hasDefinition(for word: String) -> Bool {
        return getDefinition(for: word) != nil
    }
    
    /// Format definition for display (clean up and structure)
    /// - Parameter definition: Raw definition from DCSCopyTextDefinition
    /// - Returns: Formatted definition string
    func formatDefinition(_ definition: String) -> String {
        // The raw definition from DCS often has the word and pronunciation at the start
        // Format: "word | pronunciation | part_of_speech definition..."
        
        var formatted = definition
        
        // Clean up multiple spaces
        formatted = formatted.replacingOccurrences(of: "  +", with: " ", options: .regularExpression)
        
        // Add line breaks before numbered definitions (1, 2, 3, etc.)
        formatted = formatted.replacingOccurrences(
            of: "([^0-9])([0-9]+)\\s+",
            with: "$1\n\n$2 ",
            options: .regularExpression
        )
        
        // Add line break before parts of speech indicators
        let partsOfSpeech = ["noun", "verb", "adjective", "adverb", "pronoun", "preposition", "conjunction", "interjection", "determiner"]
        for pos in partsOfSpeech {
            formatted = formatted.replacingOccurrences(
                of: " \(pos) ",
                with: "\n\n\(pos.capitalized)\n",
                options: .caseInsensitive
            )
        }
        
        // Add line break before "PHRASES" or "DERIVATIVES" sections
        formatted = formatted.replacingOccurrences(of: "PHRASES", with: "\n\nPHRASES")
        formatted = formatted.replacingOccurrences(of: "DERIVATIVES", with: "\n\nDERIVATIVES")
        formatted = formatted.replacingOccurrences(of: "ORIGIN", with: "\n\nORIGIN")
        
        return formatted.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    
    // MARK: - Word Completions
    
    /// Get word completions for a given prefix
    /// - Parameters:
    ///   - prefix: The partial word to complete
    ///   - language: Language code (e.g., "en", "en_US", "vi")
    /// - Returns: Array of possible completions (full words)
    func completions(for prefix: String, language: String = "en") -> [String] {
        guard !prefix.isEmpty, prefix.count >= 2 else { return [] }
        
        let cacheKey = "\(prefix.lowercased())_\(language)"
        
        // Check cache first
        if let cached = completionCache[cacheKey] {
            return cached
        }
        
        let range = NSRange(location: 0, length: prefix.utf16.count)
        let results = spellChecker.completions(
            forPartialWordRange: range,
            in: prefix,
            language: language,
            inSpellDocumentWithTag: 0
        ) ?? []
        
        // Cache the results
        if completionCache.count >= maxCacheSize {
            // Remove oldest entry (simple cleanup)
            if let firstKey = completionCache.keys.first {
                completionCache.removeValue(forKey: firstKey)
            }
        }
        completionCache[cacheKey] = results
        
        return results
    }
    
    /// Get the first completion suggestion (only the suffix part)
    /// - Parameters:
    ///   - prefix: The partial word typed by user
    ///   - language: Language code
    ///   - minWordLength: Minimum length of the completed word
    /// - Returns: The completion suffix (part to append), or nil if none found
    func getCompletionSuffix(for prefix: String, language: String = "en", minWordLength: Int = 4) -> String? {
        let allCompletions = completions(for: prefix, language: language)
        
        // Find first completion that:
        // 1. Is longer than the prefix (not exact match)
        // 2. Meets minimum word length
        guard let match = allCompletions.first(where: {
            $0.lowercased() != prefix.lowercased() && $0.count >= minWordLength
        }) else {
            return nil
        }
        
        // Return only the suffix (part after prefix)
        let completionStartIndex = match.index(match.startIndex, offsetBy: prefix.count)
        return String(match[completionStartIndex...])
    }
    
    // MARK: - Word Validation
    
    /// Check if a word exists in the system dictionary
    /// - Parameters:
    ///   - word: The word to check
    ///   - language: Language code
    /// - Returns: true if word is valid/spelled correctly
    func wordExists(_ word: String, language: String = "en") -> Bool {
        let range = spellChecker.checkSpelling(
            of: word,
            startingAt: 0,
            language: language,
            wrap: false,
            inSpellDocumentWithTag: 0,
            wordCount: nil
        )
        // If no misspelling found, word exists
        return range.location == NSNotFound
    }
    
    /// Get spelling suggestions for a potentially misspelled word
    /// - Parameters:
    ///   - word: The potentially misspelled word
    ///   - language: Language code
    /// - Returns: Array of suggested corrections
    func spellingSuggestions(for word: String, language: String = "en") -> [String] {
        let range = NSRange(location: 0, length: word.utf16.count)
        return spellChecker.guesses(
            forWordRange: range,
            in: word,
            language: language,
            inSpellDocumentWithTag: 0
        ) ?? []
    }
    
    // MARK: - Cache Management
    
    /// Clear all caches
    func clearCache() {
        completionCache.removeAll()
        definitionCache.removeAll()
    }
}
#endif
