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

    // HashSet for O(1) duplicate checking and existence lookup
    private var bundledWordSet: Set<String> = []
    private var customWordSet: Set<String> = []

    // Sorted arrays for O(log n) binary search with prefix matching
    private var bundledWordsSorted: [String] = []
    private var customWordsSorted: [String] = []
    private var allWordsSorted: [String] = []

    // Prefix cache for O(1) repeated queries (max 100 entries to prevent memory bloat)
    private var prefixCache: [String: [String]] = [:]
    private let maxCacheSize = 100

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
            let words = parseWords(from: content)
            bundledWordSet = Set(words) // O(n) - deduplicate automatically
            bundledWordsSorted = bundledWordSet.sorted() // O(n log n) - sort once
            rebuildCombinedWordList()
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
        rebuildCombinedWordList()
        clearCache()
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
            rebuildCombinedWordList()
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

        // Use Set for automatic deduplication - O(n)
        customWordSet = Set(tempWords)
        customWordsSorted = customWordSet.sorted() // O(n log n) - sort once
        rebuildCombinedWordList()
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

    // Rebuild combined sorted word list when sources change
    private func rebuildCombinedWordList() {
        var combinedSet: Set<String> = []
        if useBuiltIn {
            combinedSet.formUnion(bundledWordSet)
        }
        combinedSet.formUnion(customWordSet)
        allWordsSorted = combinedSet.sorted() // O(n log n) - sort combined list once
    }

    // Clear prefix cache
    private func clearCache() {
        prefixCache.removeAll()
    }

    // OPTIMIZED: HashSet + Binary Search + Caching
    // Time complexity: O(log n + k) where k = number of matches (typically < 10)
    // Space complexity: O(n + c) where c = cache size (max 100)
    func getSuggestion(for prefix: String) -> String? {
        guard !prefix.isEmpty else { return nil }
        let lowercasedPrefix = prefix.lowercased()

        // Check cache first - O(1)
        if let cached = prefixCache[lowercasedPrefix] {
            // Return first match that meets minWordLength and isn't exact match
            return cached.first {
                $0.lowercased() != lowercasedPrefix && $0.count >= minWordLength
            }.map { word in
                // Return only completion part (without prefix)
                let completionStartIndex = word.index(word.startIndex, offsetBy: prefix.count)
                return String(word[completionStartIndex...])
            }
        }

        // Binary search to find first word >= lowercasedPrefix - O(log n)
        var matches: [String] = []

        // Binary search for starting position
        var left = 0
        var right = allWordsSorted.count
        while left < right {
            let mid = left + (right - left) / 2
            if allWordsSorted[mid].lowercased() < lowercasedPrefix {
                left = mid + 1
            } else {
                right = mid
            }
        }
        let startIndex = left

        // Linear scan from startIndex (very fast because sorted, typically finds match in < 10 iterations)
        for i in startIndex..<allWordsSorted.count {
            let word = allWordsSorted[i]
            let lowercasedWord = word.lowercased()

            if lowercasedWord.hasPrefix(lowercasedPrefix) {
                matches.append(word)
            } else {
                break // Stop when no longer matching prefix (early termination)
            }
        }

        // Cache the results (limit cache size to prevent memory bloat)
        if prefixCache.count >= maxCacheSize {
            // Remove oldest entry (simple FIFO, could use LRU for better performance)
            if let firstKey = prefixCache.keys.first {
                prefixCache.removeValue(forKey: firstKey)
            }
        }
        prefixCache[lowercasedPrefix] = matches

        // Return first match that meets criteria
        return matches.first {
            $0.lowercased() != lowercasedPrefix && $0.count >= minWordLength
        }.map { word in
            // Return only completion part (without prefix)
            let completionStartIndex = word.index(word.startIndex, offsetBy: prefix.count)
            return String(word[completionStartIndex...])
        }
    }

    // MARK: - Sentence Suggestion (Beta)
    func getSentenceSuggestion() -> String {
        // TODO: Replace this with actual sentence suggestion logic
        // This is a placeholder for future development
        return "this is a test version of sentence suggestion feature"
    }

    var customWordCount: Int {
        return customWordSet.count
    }

    var bundledWordCount: Int {
        return bundledWordSet.count
    }
}
#endif
