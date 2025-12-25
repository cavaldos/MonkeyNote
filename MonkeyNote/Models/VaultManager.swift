//
//  VaultManager.swift
//  Note
//
//  Created by Nguyen Ngoc Khanh on 24/12/25.
//

import Foundation
import SwiftUI
import Combine

class VaultManager: ObservableObject {
    @Published private(set) var vaultURL: URL?
    
    private let vaultPathKey = "vaultPath"
    private let userDefaults = UserDefaults.standard
    private let structureFileName = ".vault-structure.json"
    
    init() {
        setupVault()
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
        
        objectWillChange.send()
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
                    note.text = content
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
                    let note = NoteItem(title: title, text: content, savedTitle: title)
                    notes.append(note)
                    print("📄 Loaded note: \(title)")
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
}
