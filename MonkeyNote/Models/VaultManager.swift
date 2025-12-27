//
//  VaultManager.swift
//  Note
//
//  Created by Nguyen Ngoc Khanh on 24/12/25.
//

import Foundation
import SwiftUI
import Combine

// MARK: - Recent Vault Model

struct RecentVault: Identifiable, Codable {
    let id: UUID
    let path: String
    let lastAccessed: Date
    let folderName: String
    
    init(path: String) {
        self.id = UUID()
        self.path = path
        self.lastAccessed = Date()
        self.folderName = URL(fileURLWithPath: path).lastPathComponent
    }
}

class VaultManager: ObservableObject {
    @Published private(set) var vaultURL: URL?
    
    private let vaultPathKey = "vaultPath"
    private let userDefaults = UserDefaults.standard
    private let structureFileName = ".vault-structure.json"
    
    private let recentVaultsKey = "recentVaults"
    private let maxRecentVaults = 10
    
    @Published private(set) var recentVaults: [RecentVault] = []
    
    // MARK: - Large File Protection
    /// Maximum allowed lines for a note file (files exceeding this will not be opened) //crash
    static let maxAllowedLines: Int = 5_000
    
    init() {
        setupVault()
        loadRecentVaultsOnStartup()
    }
    
    private func setupVault() {
        if let savedPath = userDefaults.string(forKey: vaultPathKey) {
            let url = URL(fileURLWithPath: savedPath)
            if FileManager.default.fileExists(atPath: savedPath) {
                self.vaultURL = url
                print("📂 Restored vault: \(savedPath)")
                return
            }
        }
        createDefaultVault()
    }
    
    private func createDefaultVault() {
        let fileManager = FileManager.default
        
        guard let documentsURL = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first else {
            print("❌ Cannot find Documents directory")
            return
        }
        
        let notesFolder = documentsURL.appendingPathComponent("Notes")
        
        do {
            if !fileManager.fileExists(atPath: notesFolder.path) {
                try fileManager.createDirectory(at: notesFolder, withIntermediateDirectories: true, attributes: nil)
                print("📂 Created vault folder: \(notesFolder.path)")
            }
            
            self.vaultURL = notesFolder
            userDefaults.set(notesFolder.path, forKey: vaultPathKey)
            print("📂 Vault set to: \(notesFolder.path)")
            
        } catch {
            print("❌ Failed to create vault folder: \(error)")
        }
    }
    
    var hasVault: Bool {
        vaultURL != nil
    }
    
    func createVaultIfNeeded() {
        if vaultURL == nil {
            createDefaultVault()
        }
    }
    
    var vaultPath: String {
        vaultURL?.path ?? "No vault selected"
    }
    
    func setVault(url: URL) {
        let fileManager = FileManager.default
        if !fileManager.fileExists(atPath: url.path) {
            do {
                try fileManager.createDirectory(at: url, withIntermediateDirectories: true, attributes: nil)
            } catch {
                print("❌ Failed to create vault folder: \(error)")
                return
            }
        }
        
        vaultURL = url
        userDefaults.set(url.path, forKey: vaultPathKey)
        print("📂 Vault changed to: \(url.path)")
        
        // Add to recent vaults
        addToRecentVaults(path: url.path)
        
        objectWillChange.send()
    }
    
    // MARK: - Recent Vaults
    
    /// Add vault to recent vaults list
    private func addToRecentVaults(path: String) {
        var recent = loadRecentVaults()
        
        // Remove existing entry with same path
        recent.removeAll { $0.path == path }
        
        // Add new entry at beginning
        recent.insert(RecentVault(path: path), at: 0)
        
        // Keep only max recent vaults
        if recent.count > maxRecentVaults {
            recent = Array(recent.prefix(maxRecentVaults))
        }
        
        // Save to UserDefaults
        if let data = try? JSONEncoder().encode(recent) {
            userDefaults.set(data, forKey: recentVaultsKey)
        }
        
        // Update published property
        DispatchQueue.main.async {
            self.recentVaults = recent
        }
    }
    
    /// Load recent vaults from UserDefaults
    private func loadRecentVaults() -> [RecentVault] {
        guard let data = userDefaults.data(forKey: recentVaultsKey),
              let recent = try? JSONDecoder().decode([RecentVault].self, from: data) else {
            return []
        }
        
        // Filter out vaults that no longer exist
        let existing = recent.filter { FileManager.default.fileExists(atPath: $0.path) }
        
        // If some vaults were removed, update UserDefaults
        if existing.count != recent.count {
            if let data = try? JSONEncoder().encode(existing) {
                userDefaults.set(data, forKey: recentVaultsKey)
            }
        }
        
        return existing
    }
    
    /// Load recent vaults on startup
    private func loadRecentVaultsOnStartup() {
        let recent = loadRecentVaults()
        DispatchQueue.main.async {
            self.recentVaults = recent
        }
    }
    
    /// Remove vault from recent list
    func removeFromRecentVaults(id: UUID) {
        recentVaults.removeAll { $0.id == id }
        
        if let data = try? JSONEncoder().encode(recentVaults) {
            userDefaults.set(data, forKey: recentVaultsKey)
        }
    }
    
    /// Clear all recent vaults
    func clearRecentVaults() {
        recentVaults = []
        userDefaults.removeObject(forKey: recentVaultsKey)
    }
    
    // MARK: - Save/Load Folder Structure + Notes
    
    /// Save entire folder structure and all notes to disk
    /// Returns updated folders with savedTitle synced to title
    @discardableResult
    func saveFolders(_ folders: [NoteFolder]) -> [NoteFolder] {
        guard let vaultURL = vaultURL else {
            print("❌ No vault selected")
            return folders
        }
        
        // Save all notes as .md files in folder hierarchy (handles renames)
        let updatedFolders = saveNotesRecursively(folders: folders, baseURL: vaultURL)
        
        // Save structure to JSON (with updated savedTitle values)
        let structureURL = vaultURL.appendingPathComponent(structureFileName)
        let vaultData = VaultData(folders: updatedFolders)
        
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            encoder.dateEncodingStrategy = .iso8601
            let data = try encoder.encode(vaultData)
            try data.write(to: structureURL)
            print("✅ Saved vault structure")
        } catch {
            print("❌ Failed to save structure: \(error)")
        }
        
        return updatedFolders
    }
    
    private func saveNotesRecursively(folders: [NoteFolder], baseURL: URL) -> [NoteFolder] {
        let fileManager = FileManager.default
        var updatedFolders: [NoteFolder] = []
        
        for var folder in folders {
            let newFolderName = sanitizeFileName(folder.name)
            let oldFolderName = sanitizeFileName(folder.savedName)
            let newFolderURL = baseURL.appendingPathComponent(newFolderName)
            let oldFolderURL = baseURL.appendingPathComponent(oldFolderName)
            
            // If folder name changed, rename the folder on disk
            if newFolderName != oldFolderName && fileManager.fileExists(atPath: oldFolderURL.path) {
                do {
                    try fileManager.moveItem(at: oldFolderURL, to: newFolderURL)
                    print("🔄 Renamed folder: \(oldFolderName) → \(newFolderName)")
                    folder.savedName = folder.name
                } catch {
                    print("❌ Failed to rename folder \(oldFolderName): \(error)")
                    // If rename fails, try to create new folder
                    if !fileManager.fileExists(atPath: newFolderURL.path) {
                        try? fileManager.createDirectory(at: newFolderURL, withIntermediateDirectories: true)
                        folder.savedName = folder.name
                    }
                }
            } else if !fileManager.fileExists(atPath: newFolderURL.path) {
                // Create folder on disk if it doesn't exist
                do {
                    try fileManager.createDirectory(at: newFolderURL, withIntermediateDirectories: true)
                    print("📁 Created folder: \(folder.name)")
                    folder.savedName = folder.name
                } catch {
                    print("❌ Failed to create folder \(folder.name): \(error)")
                    updatedFolders.append(folder)
                    continue
                }
            } else {
                // Folder exists, just update savedName
                folder.savedName = folder.name
            }
            
            // Save notes in this folder
            var updatedNotes: [NoteItem] = []
            for var note in folder.notes {
                let newFileName = sanitizeFileName(note.title) + ".md"
                let oldFileName = sanitizeFileName(note.savedTitle) + ".md"
                let newFileURL = newFolderURL.appendingPathComponent(newFileName)
                let oldFileURL = newFolderURL.appendingPathComponent(oldFileName)
                
                // If title changed, delete the old file first
                if newFileName != oldFileName && fileManager.fileExists(atPath: oldFileURL.path) {
                    do {
                        try fileManager.removeItem(at: oldFileURL)
                        print("🔄 Renamed: \(oldFileName) → \(newFileName)")
                    } catch {
                        print("❌ Failed to delete old file \(oldFileName): \(error)")
                    }
                }
                
                // Save the note with new filename
                do {
                    try note.text.write(to: newFileURL, atomically: true, encoding: .utf8)
                    print("💾 Saved: \(folder.name)/\(newFileName)")
                    // Update savedTitle to match current title
                    note.savedTitle = note.title
                } catch {
                    print("❌ Failed to save \(newFileName): \(error)")
                }
                
                updatedNotes.append(note)
            }
            folder.notes = updatedNotes
            
            // Recurse into children
            if !folder.children.isEmpty {
                folder.children = saveNotesRecursively(folders: folder.children, baseURL: newFolderURL)
            }
            
            updatedFolders.append(folder)
        }
        
        return updatedFolders
    }
    
    /// Load folder structure from JSON, or scan disk if no structure exists
    func loadFolders() -> [NoteFolder] {
        guard let vaultURL = vaultURL else {
            print("❌ No vault to load from")
            return []
        }
        
        let structureURL = vaultURL.appendingPathComponent(structureFileName)
        
        // Try to load from JSON structure
        if FileManager.default.fileExists(atPath: structureURL.path) {
            do {
                let data = try Data(contentsOf: structureURL)
                let decoder = JSONDecoder()
                decoder.dateDecodingStrategy = .iso8601
                let vaultData = try decoder.decode(VaultData.self, from: data)
                print("✅ Loaded vault structure with \(vaultData.folders.count) folders")
                
                // Reload note contents from .md files
                return reloadNoteContents(folders: vaultData.folders, baseURL: vaultURL)
            } catch {
                print("⚠️ Failed to load structure, scanning disk: \(error)")
            }
        }
        
        // Fallback: scan disk and create structure
        return scanDiskForFolders(at: vaultURL)
    }
    
    /// Reload note contents from .md files (in case they were edited externally)
    private func reloadNoteContents(folders: [NoteFolder], baseURL: URL) -> [NoteFolder] {
        var updatedFolders: [NoteFolder] = []
        
        for var folder in folders {
            let folderURL = baseURL.appendingPathComponent(sanitizeFileName(folder.name))
            
            // Reload each note's content
            var updatedNotes: [NoteItem] = []
            for var note in folder.notes {
                let fileName = sanitizeFileName(note.title) + ".md"
                let fileURL = folderURL.appendingPathComponent(fileName)
                
                if let content = try? String(contentsOf: fileURL, encoding: .utf8) {
                    let lineCount = content.components(separatedBy: .newlines).count
                    
                    // Check if file exceeds maximum allowed lines
                    if lineCount > VaultManager.maxAllowedLines {
                        note.text = ""
                        note.isTooLarge = true
                        note.lineCount = lineCount
                    } else {
                        note.text = content
                        note.isTooLarge = false
                        note.lineCount = lineCount
                    }
                }
                updatedNotes.append(note)
            }
            folder.notes = updatedNotes
            
            // Recurse into children
            if !folder.children.isEmpty {
                folder.children = reloadNoteContents(folders: folder.children, baseURL: folderURL)
            }
            
            updatedFolders.append(folder)
        }
        
        return updatedFolders
    }
    
    /// Scan disk to build folder structure (fallback when no JSON exists)
    private func scanDiskForFolders(at url: URL) -> [NoteFolder] {
        let fileManager = FileManager.default
        var folders: [NoteFolder] = []
        
        do {
            let contents = try fileManager.contentsOfDirectory(
                at: url,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsHiddenFiles]
            )
            
            for item in contents {
                let isDirectory = (try? item.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory ?? false
                
                if isDirectory {
                    // It's a folder - scan it recursively
                    let folderName = item.lastPathComponent
                    let children = scanDiskForFolders(at: item)
                    let notes = loadNotesFromFolder(at: item)
                    
                    let folder = NoteFolder(name: folderName, savedName: folderName, notes: notes, children: children)
                    folders.append(folder)
                    print("📁 Scanned folder: \(folderName)")
                }
            }
        } catch {
            print("❌ Failed to scan \(url.path): \(error)")
        }
        
        return folders.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }
    
    /// Load all .md notes from a specific folder
    private func loadNotesFromFolder(at url: URL) -> [NoteItem] {
        let fileManager = FileManager.default
        var notes: [NoteItem] = []
        
        do {
            let files = try fileManager.contentsOfDirectory(
                at: url,
                includingPropertiesForKeys: [.contentModificationDateKey],
                options: [.skipsHiddenFiles]
            )
            
            for file in files {
                guard file.pathExtension.lowercased() == "md" else { continue }
                
                do {
                    let content = try String(contentsOf: file, encoding: .utf8)
                    let title = file.deletingPathExtension().lastPathComponent
                    let lineCount = content.components(separatedBy: .newlines).count
                    
                    // Check if file exceeds maximum allowed lines
                    if lineCount > VaultManager.maxAllowedLines {
                        // File too large - create note without content
                        let note = NoteItem(
                            title: title,
                            text: "",
                            savedTitle: title,
                            isTooLarge: true,
                            lineCount: lineCount
                        )
                        notes.append(note)
                        print("⚠️ Note too large (\(lineCount) lines): \(title)")
                    } else {
                        // Normal file - load content
                        let note = NoteItem(
                            title: title,
                            text: content,
                            savedTitle: title,
                            isTooLarge: false,
                            lineCount: lineCount
                        )
                        notes.append(note)
                        print("📄 Loaded note: \(title)")
                    }
                } catch {
                    print("❌ Failed to read \(file.lastPathComponent): \(error)")
                }
            }
        } catch {
            print("❌ Failed to list files in \(url.path): \(error)")
        }
        
        return notes.sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
    }
    
    // MARK: - Single Note Operations
    
    /// Save a single note (used for debounced saves)
    func saveNote(note: NoteItem, inFolder folderPath: [String]) {
        guard let vaultURL = vaultURL else { return }
        
        var fileURL = vaultURL
        for folderName in folderPath {
            fileURL = fileURL.appendingPathComponent(sanitizeFileName(folderName))
        }
        
        // Ensure folder exists
        let fileManager = FileManager.default
        if !fileManager.fileExists(atPath: fileURL.path) {
            try? fileManager.createDirectory(at: fileURL, withIntermediateDirectories: true)
        }
        
        let fileName = sanitizeFileName(note.title) + ".md"
        fileURL = fileURL.appendingPathComponent(fileName)
        
        do {
            try note.text.write(to: fileURL, atomically: true, encoding: .utf8)
            print("💾 Saved: \(fileName)")
        } catch {
            print("❌ Failed to save \(fileName): \(error)")
        }
    }
    
    /// Delete a note file
    func deleteNote(title: String, inFolder folderPath: [String]) {
        guard let vaultURL = vaultURL else { return }
        
        var fileURL = vaultURL
        for folderName in folderPath {
            fileURL = fileURL.appendingPathComponent(sanitizeFileName(folderName))
        }
        
        let fileName = sanitizeFileName(title) + ".md"
        fileURL = fileURL.appendingPathComponent(fileName)
        
        do {
            try FileManager.default.removeItem(at: fileURL)
            print("🗑️ Deleted: \(fileName)")
        } catch {
            print("❌ Failed to delete \(fileName): \(error)")
        }
    }
    
    /// Rename a note file (delete old, save new)
    func renameNote(oldTitle: String, newTitle: String, inFolder folderPath: [String]) {
        guard let vaultURL = vaultURL else { return }
        guard oldTitle != newTitle else { return }
        
        var folderURL = vaultURL
        for folderName in folderPath {
            folderURL = folderURL.appendingPathComponent(sanitizeFileName(folderName))
        }
        
        let oldFileName = sanitizeFileName(oldTitle) + ".md"
        let oldFileURL = folderURL.appendingPathComponent(oldFileName)
        
        // Delete old file if it exists
        if FileManager.default.fileExists(atPath: oldFileURL.path) {
            do {
                try FileManager.default.removeItem(at: oldFileURL)
                print("🔄 Renamed: \(oldFileName) → \(sanitizeFileName(newTitle)).md")
            } catch {
                print("❌ Failed to delete old file \(oldFileName): \(error)")
            }
        }
    }
    
    /// Delete a folder and all its contents
    func deleteFolder(name: String, inFolder parentPath: [String]) {
        guard let vaultURL = vaultURL else { return }
        
        var folderURL = vaultURL
        for folderName in parentPath {
            folderURL = folderURL.appendingPathComponent(sanitizeFileName(folderName))
        }
        folderURL = folderURL.appendingPathComponent(sanitizeFileName(name))
        
        do {
            try FileManager.default.removeItem(at: folderURL)
            print("🗑️ Deleted folder: \(name)")
        } catch {
            print("❌ Failed to delete folder \(name): \(error)")
        }
    }
    
    // MARK: - Helpers
    
    private func sanitizeFileName(_ name: String) -> String {
        // Chỉ giữ lại chữ cái, số, khoảng trắng, gạch nối và gạch dưới
        let allowedCharacters = CharacterSet.alphanumerics
            .union(CharacterSet(charactersIn: " -_"))
        
        var sanitized = ""
        for character in name {
            if allowedCharacters.contains(character.unicodeScalars.first!) {
                sanitized += String(character)
            }
        }
        
        // Thay thế nhiều khoảng trắng liên tiếp bằng một khoảng trắng
        sanitized = sanitized.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
        
        // Xóa khoảng trắng ở đầu và cuối
        sanitized = sanitized.trimmingCharacters(in: .whitespacesAndNewlines)
        
        // Xóa dấu chấm ở đầu
        while sanitized.hasPrefix(".") {
            sanitized.removeFirst()
        }
        
        return sanitized.isEmpty ? "Untitled" : sanitized
    }
    
    // MARK: - Trash Management
    
    /// Scan vault for orphan files/folders not in structure (trash items)
    func scanTrash(currentFolders: [NoteFolder]) -> [TrashItem] {
        guard let vaultURL = vaultURL else { return [] }
        
        // Build set of known paths from current structure
        var knownPaths = Set<String>()
        collectKnownPaths(folders: currentFolders, basePath: "", into: &knownPaths)
        
        // Scan disk and find orphans
        var trashItems: [TrashItem] = []
        scanForOrphans(at: vaultURL, relativePath: "", knownPaths: knownPaths, into: &trashItems)
        
        return trashItems.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }
    
    /// Collect all known paths from folder structure
    private func collectKnownPaths(folders: [NoteFolder], basePath: String, into paths: inout Set<String>) {
        for folder in folders {
            let folderPath = basePath.isEmpty ? sanitizeFileName(folder.name) : "\(basePath)/\(sanitizeFileName(folder.name))"
            paths.insert(folderPath)
            
            // Add all notes in this folder
            for note in folder.notes {
                let notePath = "\(folderPath)/\(sanitizeFileName(note.title)).md"
                paths.insert(notePath)
            }
            
            // Recurse into children
            if !folder.children.isEmpty {
                collectKnownPaths(folders: folder.children, basePath: folderPath, into: &paths)
            }
        }
    }
    
    /// Scan disk recursively to find orphan items
    private func scanForOrphans(at url: URL, relativePath: String, knownPaths: Set<String>, into trashItems: inout [TrashItem]) {
        let fileManager = FileManager.default
        
        do {
            let contents = try fileManager.contentsOfDirectory(
                at: url,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsHiddenFiles]
            )
            
            for item in contents {
                let itemName = item.lastPathComponent
                let itemRelativePath = relativePath.isEmpty ? itemName : "\(relativePath)/\(itemName)"
                let isDirectory = (try? item.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory ?? false
                
                if isDirectory {
                    // Check if this folder is known
                    if !knownPaths.contains(itemRelativePath) {
                        // Entire folder is orphan
                        let trashItem = TrashItem(
                            name: itemName,
                            type: .folder,
                            relativePath: itemRelativePath,
                            fullURL: item
                        )
                        trashItems.append(trashItem)
                        // Don't recurse into orphan folders - they'll be deleted entirely
                    } else {
                        // Folder is known, scan inside for orphan files
                        scanForOrphans(at: item, relativePath: itemRelativePath, knownPaths: knownPaths, into: &trashItems)
                    }
                } else if itemName.hasSuffix(".md") {
                    // Check if this file is known
                    if !knownPaths.contains(itemRelativePath) {
                        let trashItem = TrashItem(
                            name: itemName,
                            type: .file,
                            relativePath: itemRelativePath,
                            fullURL: item
                        )
                        trashItems.append(trashItem)
                    }
                }
            }
        } catch {
            print("❌ Failed to scan for orphans at \(url.path): \(error)")
        }
    }
    
    /// Permanently delete a single trash item
    func deleteTrashItem(_ item: TrashItem) {
        do {
            try FileManager.default.removeItem(at: item.fullURL)
            print("🗑️ Permanently deleted: \(item.relativePath)")
        } catch {
            print("❌ Failed to delete \(item.relativePath): \(error)")
        }
    }
    
    /// Empty all trash (permanently delete all orphan items)
    func emptyTrash(items: [TrashItem]) {
        for item in items {
            deleteTrashItem(item)
        }
        print("🗑️ Trash emptied")
    }
    
    /// Restore a trash item back to the folder structure
    func restoreTrashItem(_ item: TrashItem, into folders: inout [NoteFolder]) {
        guard let vaultURL = vaultURL else { return }
        
        let pathComponents = item.relativePath.components(separatedBy: "/")
        
        if item.type == .file {
            // Restore file: find or create parent folder, then add note
            let folderComponents = Array(pathComponents.dropLast())
            let fileName = pathComponents.last ?? item.name
            let noteTitle = fileName.replacingOccurrences(of: ".md", with: "")
            
            // Read file content
            let content = (try? String(contentsOf: item.fullURL, encoding: .utf8)) ?? ""
            let note = NoteItem(title: noteTitle, text: content, savedTitle: noteTitle)
            
            if folderComponents.isEmpty {
                // This shouldn't happen - files should be in folders
                print("⚠️ Cannot restore file at root level")
            } else {
                // Find or create the parent folder path
                ensureFolderPath(folderComponents, in: &folders)
                addNoteToFolder(note, atPath: folderComponents, in: &folders)
            }
        } else {
            // Restore folder: scan it and add to structure
            let parentComponents = Array(pathComponents.dropLast())
            let restoredFolder = scanSingleFolder(at: item.fullURL, name: item.name)
            
            if parentComponents.isEmpty {
                // Add at root level
                folders.append(restoredFolder)
            } else {
                // Add under parent folder
                ensureFolderPath(parentComponents, in: &folders)
                addSubfolderToPath(restoredFolder, atPath: parentComponents, in: &folders)
            }
        }
        
        print("♻️ Restored: \(item.relativePath)")
    }
    
    /// Ensure folder path exists in structure
    private func ensureFolderPath(_ pathComponents: [String], in folders: inout [NoteFolder]) {
        guard !pathComponents.isEmpty else { return }
        
        let firstComponent = pathComponents[0]
        
        // Find or create first level folder
        if let index = folders.firstIndex(where: { sanitizeFileName($0.name) == firstComponent }) {
            // Folder exists, recurse if needed
            if pathComponents.count > 1 {
                let remaining = Array(pathComponents.dropFirst())
                ensureFolderPath(remaining, in: &folders[index].children)
            }
        } else {
            // Create folder
            var newFolder = NoteFolder(name: firstComponent, savedName: firstComponent)
            if pathComponents.count > 1 {
                let remaining = Array(pathComponents.dropFirst())
                ensureFolderPath(remaining, in: &newFolder.children)
            }
            folders.append(newFolder)
        }
    }
    
    /// Add note to folder at path
    private func addNoteToFolder(_ note: NoteItem, atPath pathComponents: [String], in folders: inout [NoteFolder]) {
        guard !pathComponents.isEmpty else { return }
        
        let firstComponent = pathComponents[0]
        
        if let index = folders.firstIndex(where: { sanitizeFileName($0.name) == firstComponent }) {
            if pathComponents.count == 1 {
                // This is the target folder
                folders[index].notes.append(note)
            } else {
                let remaining = Array(pathComponents.dropFirst())
                addNoteToFolder(note, atPath: remaining, in: &folders[index].children)
            }
        }
    }
    
    /// Add subfolder to path
    private func addSubfolderToPath(_ subfolder: NoteFolder, atPath pathComponents: [String], in folders: inout [NoteFolder]) {
        guard !pathComponents.isEmpty else { return }
        
        let firstComponent = pathComponents[0]
        
        if let index = folders.firstIndex(where: { sanitizeFileName($0.name) == firstComponent }) {
            if pathComponents.count == 1 {
                // This is the target parent folder
                folders[index].children.append(subfolder)
            } else {
                let remaining = Array(pathComponents.dropFirst())
                addSubfolderToPath(subfolder, atPath: remaining, in: &folders[index].children)
            }
        }
    }
    
    /// Scan a single folder from disk (for restore)
    private func scanSingleFolder(at url: URL, name: String) -> NoteFolder {
        let notes = loadNotesFromFolder(at: url)
        let children = scanDiskForFolders(at: url)
        return NoteFolder(name: name, savedName: name, notes: notes, children: children)
    }
    
    // MARK: - Move Operations (Drag & Drop)
    
    /// Di chuyển file note từ folder này sang folder khác trên disk
    /// - Parameters:
    ///   - noteTitle: Tên note (không có .md)
    ///   - fromFolderNames: Đường dẫn folder nguồn (mảng tên folder từ root)
    ///   - toFolderNames: Đường dẫn folder đích (mảng tên folder từ root)
    /// - Returns: true nếu thành công
    @discardableResult
    func moveNoteFile(noteTitle: String, fromFolderNames: [String], toFolderNames: [String]) -> Bool {
        guard let vaultURL = vaultURL else {
            print("❌ No vault selected")
            return false
        }
        
        let fileManager = FileManager.default
        let fileName = sanitizeFileName(noteTitle) + ".md"
        
        // Build source path
        var sourceURL = vaultURL
        for folderName in fromFolderNames {
            sourceURL = sourceURL.appendingPathComponent(sanitizeFileName(folderName))
        }
        sourceURL = sourceURL.appendingPathComponent(fileName)
        
        // Build destination path
        var destURL = vaultURL
        for folderName in toFolderNames {
            destURL = destURL.appendingPathComponent(sanitizeFileName(folderName))
        }
        
        // Ensure destination folder exists
        if !fileManager.fileExists(atPath: destURL.path) {
            do {
                try fileManager.createDirectory(at: destURL, withIntermediateDirectories: true)
            } catch {
                print("❌ Failed to create destination folder: \(error)")
                return false
            }
        }
        
        destURL = destURL.appendingPathComponent(fileName)
        
        // Move the file
        do {
            // If destination file exists, remove it first
            if fileManager.fileExists(atPath: destURL.path) {
                try fileManager.removeItem(at: destURL)
            }
            try fileManager.moveItem(at: sourceURL, to: destURL)
            print("📦 Moved note: \(fileName) → \(toFolderNames.joined(separator: "/"))")
            return true
        } catch {
            print("❌ Failed to move note \(fileName): \(error)")
            return false
        }
    }
    
    /// Di chuyển toàn bộ folder sang vị trí mới trên disk
    /// - Parameters:
    ///   - folderName: Tên folder cần di chuyển
    ///   - fromParentNames: Đường dẫn folder cha nguồn (mảng tên folder từ root, rỗng = root)
    ///   - toParentNames: Đường dẫn folder cha đích (mảng tên folder từ root, rỗng = root)
    /// - Returns: true nếu thành công
    @discardableResult
    func moveFolderOnDisk(folderName: String, fromParentNames: [String], toParentNames: [String]) -> Bool {
        guard let vaultURL = vaultURL else {
            print("❌ No vault selected")
            return false
        }
        
        let fileManager = FileManager.default
        let sanitizedFolderName = sanitizeFileName(folderName)
        
        // Build source path
        var sourceURL = vaultURL
        for name in fromParentNames {
            sourceURL = sourceURL.appendingPathComponent(sanitizeFileName(name))
        }
        sourceURL = sourceURL.appendingPathComponent(sanitizedFolderName)
        
        // Build destination parent path
        var destParentURL = vaultURL
        for name in toParentNames {
            destParentURL = destParentURL.appendingPathComponent(sanitizeFileName(name))
        }
        
        // Ensure destination parent folder exists
        if !fileManager.fileExists(atPath: destParentURL.path) {
            do {
                try fileManager.createDirectory(at: destParentURL, withIntermediateDirectories: true)
            } catch {
                print("❌ Failed to create destination parent folder: \(error)")
                return false
            }
        }
        
        let destURL = destParentURL.appendingPathComponent(sanitizedFolderName)
        
        // Check if source exists
        guard fileManager.fileExists(atPath: sourceURL.path) else {
            print("⚠️ Source folder doesn't exist: \(sourceURL.path)")
            return false
        }
        
        // Move the folder
        do {
            // If destination folder exists, we need to handle conflict
            if fileManager.fileExists(atPath: destURL.path) {
                // Generate unique name
                var uniqueName = sanitizedFolderName
                var counter = 1
                var uniqueDestURL = destURL
                while fileManager.fileExists(atPath: uniqueDestURL.path) {
                    uniqueName = "\(sanitizedFolderName) \(counter)"
                    uniqueDestURL = destParentURL.appendingPathComponent(uniqueName)
                    counter += 1
                }
                try fileManager.moveItem(at: sourceURL, to: uniqueDestURL)
                print("📦 Moved folder: \(folderName) → \(toParentNames.joined(separator: "/"))/\(uniqueName)")
            } else {
                try fileManager.moveItem(at: sourceURL, to: destURL)
                print("📦 Moved folder: \(folderName) → \(toParentNames.joined(separator: "/"))")
            }
            return true
        } catch {
            print("❌ Failed to move folder \(folderName): \(error)")
            return false
        }
    }
    
    /// Lấy đường dẫn folder names từ root đến folder có ID cho trước
    func getFolderPath(folderID: UUID, in folders: [NoteFolder], currentPath: [String] = []) -> [String]? {
        for folder in folders {
            let newPath = currentPath + [folder.name]
            if folder.id == folderID {
                return newPath
            }
            if let found = getFolderPath(folderID: folderID, in: folder.children, currentPath: newPath) {
                return found
            }
        }
        return nil
    }
    
    /// Lấy đường dẫn folder cha (parent path) của folder có ID cho trước
    func getParentFolderPath(folderID: UUID, in folders: [NoteFolder], currentPath: [String] = []) -> [String]? {
        for folder in folders {
            // Check if this folder contains the target as direct child
            if folder.children.contains(where: { $0.id == folderID }) {
                return currentPath + [folder.name]
            }
            // Recurse into children
            let newPath = currentPath + [folder.name]
            if let found = getParentFolderPath(folderID: folderID, in: folder.children, currentPath: newPath) {
                return found
            }
        }
        return nil
    }
}
