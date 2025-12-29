//
//  DictionaryService.swift
//  MonkeyNote
//
//  Created by Nguyen Ngoc Khanh on 29/12/25.
//

#if os(macOS)
import Foundation
import AppKit

/// Service for interacting with macOS system dictionary via NSSpellChecker
class DictionaryService {
    static let shared = DictionaryService()
    
    private let spellChecker = NSSpellChecker.shared
    
    // Cache for completions to avoid repeated lookups
    private var completionCache: [String: [String]] = [:]
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
    
    /// Clear the completion cache
    func clearCache() {
        completionCache.removeAll()
    }
}
#endif
