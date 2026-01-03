//
//  RipgrepService.swift
//  MonkeyNote
//
//  Created by Assistant on 03/01/26.
//

import Foundation

// MARK: - Search Options

struct SearchOptions {
    var isRegex: Bool = false
    var caseSensitive: Bool = false
    var maxResults: Int = 500
    var fileExtensions: [String] = ["md", "markdown", "txt"]
    
    static var `default`: SearchOptions {
        SearchOptions()
    }
}

// MARK: - Search Result (Simple - just file paths)

struct GlobalSearchResult {
    let matchingFiles: Set<String>     // Set of relative file paths that have matches
    let searchTime: TimeInterval
    let query: String
    
    static var empty: GlobalSearchResult {
        GlobalSearchResult(
            matchingFiles: [],
            searchTime: 0,
            query: ""
        )
    }
}

// MARK: - Ripgrep Service

class RipgrepService {
    static let shared = RipgrepService()
    
    private init() {}
    
    // MARK: - Get Binary Path
    
    private func getRipgrepPath() -> String? {
        // First, check in app bundle
        if let bundlePath = Bundle.main.path(forResource: "rg", ofType: nil, inDirectory: "bin") {
            return bundlePath
        }
        
        // Check in Resources/bin (development)
        if let resourcePath = Bundle.main.resourcePath {
            let devPath = (resourcePath as NSString).appendingPathComponent("bin/rg")
            if FileManager.default.fileExists(atPath: devPath) {
                return devPath
            }
        }
        
        // Check project directory (for development)
        let projectPaths = [
            "MonkeyNote/Resources/bin/rg",
            "../MonkeyNote/Resources/bin/rg"
        ]
        
        for path in projectPaths {
            let fullPath = (FileManager.default.currentDirectoryPath as NSString).appendingPathComponent(path)
            if FileManager.default.fileExists(atPath: fullPath) {
                return fullPath
            }
        }
        
        // Last resort: check common installation paths
        let systemPaths = [
            "/usr/local/bin/rg",
            "/opt/homebrew/bin/rg",
            "/usr/bin/rg"
        ]
        
        for path in systemPaths {
            if FileManager.default.fileExists(atPath: path) {
                return path
            }
        }
        
        return nil
    }
    
    // MARK: - Search (Returns matching file paths only)
    
    func search(
        query: String,
        in vaultURL: URL,
        options: SearchOptions = .default
    ) async throws -> GlobalSearchResult {
        let startTime = Date()
        
        // Validate query
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedQuery.isEmpty else {
            return .empty
        }
        
        // Get ripgrep binary path
        guard let rgPath = getRipgrepPath() else {
            print("❌ Ripgrep binary not found")
            throw RipgrepError.binaryNotFound
        }
        
        // Build arguments - only get file names
        var arguments: [String] = [
            "--files-with-matches",             // Only output file names
            "--max-count", "1",                 // Stop after first match per file
        ]
        
        // Case sensitivity
        if options.caseSensitive {
            arguments.append("--case-sensitive")
        } else {
            arguments.append("--ignore-case")
        }
        
        // Regex or literal
        if options.isRegex {
            arguments.append("-e")
            arguments.append(trimmedQuery)
        } else {
            arguments.append("--fixed-strings")
            arguments.append(trimmedQuery)
        }
        
        // File type filter
        for ext in options.fileExtensions {
            arguments.append("--glob")
            arguments.append("*.\(ext)")
        }
        
        // Search path
        arguments.append(vaultURL.path)
        
        // Execute ripgrep
        let process = Process()
        process.executableURL = URL(fileURLWithPath: rgPath)
        process.arguments = arguments
        process.currentDirectoryURL = vaultURL
        
        let outputPipe = Pipe()
        let errorPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = errorPipe
        
        do {
            try process.run()
        } catch {
            print("❌ Failed to run ripgrep: \(error)")
            throw RipgrepError.executionFailed(error.localizedDescription)
        }
        
        // Read output
        let outputData = outputPipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        
        // Parse results - just file paths
        var matchingFiles = Set<String>()
        
        if let output = String(data: outputData, encoding: .utf8) {
            let lines = output.components(separatedBy: .newlines)
            
            for line in lines {
                let trimmedLine = line.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmedLine.isEmpty else { continue }
                
                // Convert to relative path
                let relativePath: String
                if trimmedLine.hasPrefix(vaultURL.path) {
                    relativePath = String(trimmedLine.dropFirst(vaultURL.path.count + 1))
                } else {
                    relativePath = trimmedLine
                }
                
                matchingFiles.insert(relativePath)
            }
        }
        
        let searchTime = Date().timeIntervalSince(startTime)
        
        return GlobalSearchResult(
            matchingFiles: matchingFiles,
            searchTime: searchTime,
            query: trimmedQuery
        )
    }
    
    // MARK: - Check Availability
    
    var isAvailable: Bool {
        getRipgrepPath() != nil
    }
    
    var binaryPath: String? {
        getRipgrepPath()
    }
}

// MARK: - Errors

enum RipgrepError: LocalizedError {
    case binaryNotFound
    case executionFailed(String)
    case invalidOutput
    case invalidRegex(String)
    
    var errorDescription: String? {
        switch self {
        case .binaryNotFound:
            return "Ripgrep binary not found. Please run scripts/download-ripgrep.sh"
        case .executionFailed(let message):
            return "Ripgrep execution failed: \(message)"
        case .invalidOutput:
            return "Invalid output from ripgrep"
        case .invalidRegex(let pattern):
            return "Invalid regex pattern: \(pattern)"
        }
    }
}
