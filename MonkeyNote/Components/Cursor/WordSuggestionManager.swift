//
//  WordSuggestionManager.swift
//  MonkeyNote
//
//  Created by Nguyen Ngoc Khanh on 24/12/25.
//

#if os(macOS)
import Foundation
import AppKit

class WordSuggestionManager {
    static let shared = WordSuggestionManager()

    // Custom words from user's folder
    private var customWordSet: Set<String> = []
    private var customWordsSorted: [String] = []

    // Prefix cache for O(1) repeated queries (max 100 entries)
    private var prefixCache: [String: [String]] = [:]
    private let maxCacheSize = 100

    private var customFolderURL: URL?
    private var useSystemDictionary: Bool = true
    private var dictionaryLanguage: String = "en"
    private var minWordLength: Int = 4

    private init() {
        loadCustomWordsFromUserDefaults()
        useSystemDictionary = UserDefaults.standard.object(forKey: "note.useSystemDictionary") as? Bool ?? true
        dictionaryLanguage = UserDefaults.standard.string(forKey: "note.dictionaryLanguage") ?? "en"
        minWordLength = UserDefaults.standard.object(forKey: "note.minWordLength") as? Int ?? 4
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

    func setUseSystemDictionary(_ value: Bool) {
        useSystemDictionary = value
        UserDefaults.standard.set(value, forKey: "note.useSystemDictionary")
        clearCache()
    }

    func setDictionaryLanguage(_ language: String) {
        dictionaryLanguage = language
        UserDefaults.standard.set(language, forKey: "note.dictionaryLanguage")
        clearCache()
        // Also clear DictionaryService cache
        DictionaryService.shared.clearCache()
    }

    func getDictionaryLanguage() -> String {
        return dictionaryLanguage
    }

    func setMinWordLength(_ value: Int) {
        minWordLength = value
        clearCache()
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
            customWordSet = []
            customWordsSorted = []
            clearCache()
        }
    }

    func getCustomFolderURL() -> URL? {
        return customFolderURL
    }

    private func loadCustomWords(from folderURL: URL) {
        var tempWords: [String] = []

        let fileManager = FileManager.default
        guard let enumerator = fileManager.enumerator(at: folderURL, includingPropertiesForKeys: [.isRegularFileKey], options: [.skipsHiddenFiles]) else {
            return
        }

        for case let fileURL as URL in enumerator {
            if fileURL.pathExtension.lowercased() == "txt" {
                if let content = try? String(contentsOf: fileURL, encoding: .utf8) {
                    let words = parseWords(from: content)
                    tempWords.append(contentsOf: words)
                }
            }
        }

        // Use Set for automatic deduplication
        customWordSet = Set(tempWords)
        customWordsSorted = customWordSet.sorted()
        clearCache()
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

    // Clear prefix cache
    private func clearCache() {
        prefixCache.removeAll()
    }

    // MARK: - Get Suggestion

    /// Get autocomplete suggestion for a prefix
    /// Combines system dictionary and custom words
    func getSuggestion(for prefix: String) -> String? {
        guard !prefix.isEmpty else { return nil }
        let lowercasedPrefix = prefix.lowercased()

        // Check cache first
        if let cached = prefixCache[lowercasedPrefix] {
            return findBestMatch(from: cached, prefix: prefix)
        }

        var allMatches: [String] = []

        // 1. Get matches from system dictionary (via DictionaryService)
        if useSystemDictionary {
            let systemCompletions = DictionaryService.shared.completions(
                for: prefix,
                language: dictionaryLanguage
            )
            allMatches.append(contentsOf: systemCompletions)
        }

        // 2. Get matches from custom words
        let customMatches = getCustomWordMatches(for: lowercasedPrefix)
        allMatches.append(contentsOf: customMatches)

        // Remove duplicates while preserving order
        var seen = Set<String>()
        allMatches = allMatches.filter { word in
            let lowercased = word.lowercased()
            if seen.contains(lowercased) {
                return false
            }
            seen.insert(lowercased)
            return true
        }

        // Cache the results
        if prefixCache.count >= maxCacheSize {
            if let firstKey = prefixCache.keys.first {
                prefixCache.removeValue(forKey: firstKey)
            }
        }
        prefixCache[lowercasedPrefix] = allMatches

        return findBestMatch(from: allMatches, prefix: prefix)
    }

    /// Find the best match from a list of completions
    private func findBestMatch(from matches: [String], prefix: String) -> String? {
        let lowercasedPrefix = prefix.lowercased()

        // Find first match that meets criteria
        guard let match = matches.first(where: {
            $0.lowercased() != lowercasedPrefix && $0.count >= minWordLength
        }) else {
            return nil
        }

        // Return only the completion suffix (part after prefix)
        let completionStartIndex = match.index(match.startIndex, offsetBy: prefix.count)
        return String(match[completionStartIndex...])
    }

    /// Binary search for custom words matching prefix
    private func getCustomWordMatches(for prefix: String) -> [String] {
        guard !customWordsSorted.isEmpty else { return [] }

        var matches: [String] = []

        // Binary search for starting position
        var left = 0
        var right = customWordsSorted.count
        while left < right {
            let mid = left + (right - left) / 2
            if customWordsSorted[mid].lowercased() < prefix {
                left = mid + 1
            } else {
                right = mid
            }
        }
        let startIndex = left

        // Linear scan from startIndex
        for i in startIndex..<customWordsSorted.count {
            let word = customWordsSorted[i]
            let lowercasedWord = word.lowercased()

            if lowercasedWord.hasPrefix(prefix) {
                matches.append(word)
            } else {
                break // Stop when no longer matching prefix
            }
        }

        return matches
    }

    // MARK: - Sentence Suggestion (Beta)

    func getSentenceSuggestion() -> String {
        return "this is a test version of sentence suggestion feature"
    }

    // MARK: - Word Counts

    var customWordCount: Int {
        return customWordSet.count
    }

    /// System dictionary doesn't have a fixed count, return indicator
    var systemDictionaryStatus: String {
        if useSystemDictionary {
            let languageName = DictionaryService.commonLanguages.first { $0.code == dictionaryLanguage }?.name ?? dictionaryLanguage
            return "System Dictionary (\(languageName))"
        } else {
            return "Disabled"
        }
    }
}
#endif
