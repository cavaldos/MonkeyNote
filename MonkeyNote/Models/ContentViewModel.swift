//
//  ContentViewModel.swift
//  MonkeyNote
//
//  Created by Assistant on 03/01/26.
//

import SwiftUI
import Combine

#if os(iOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif

// MARK: - ContentViewModel

@Observable
final class ContentViewModel {
    
    // MARK: - Vault Manager
    var vaultManager = VaultManager()
    
    // MARK: - Data State
    var folders: [NoteFolder] = []
    var trashItems: [TrashItem] = []
    
    // MARK: - Selection State
    var selectedFolderID: NoteFolder.ID?
    var selectedNoteID: NoteItem.ID?
    
    // MARK: - Search State
    var searchText: String = ""
    var replaceText: String = ""
    var showReplaceMode: Bool = false
    var showReplacePopover: Bool = false
    var searchMatchCount: Int = 0
    var currentSearchIndex: Int = 0
    var isSearchComplete: Bool = true
    
    // MARK: - UI State
    var showSettings: Bool = false
    var showTrash: Bool = false
    var renameRequest: RenameRequest?
    var isChangingVault: Bool = false
    var showLargeFileAlert: Bool = false
    var largeFileInfo: (name: String, lines: Int)?
    
    // MARK: - External File State
    var externalFileURL: URL?
    var externalFileText: String = ""
    var isDropTargeted: Bool = false
    
    // MARK: - AppStorage (wrapped manually for @Observable)
    private var _isDarkMode: Bool = true
    var isDarkMode: Bool {
        get { UserDefaults.standard.bool(forKey: "note.isDarkMode") }
        set { UserDefaults.standard.set(newValue, forKey: "note.isDarkMode") }
    }
    
    var fontFamily: String {
        get { UserDefaults.standard.string(forKey: "note.fontFamily") ?? "monospaced" }
        set { UserDefaults.standard.set(newValue, forKey: "note.fontFamily") }
    }
    
    var fontSize: Double {
        get { UserDefaults.standard.double(forKey: "note.fontSize").nonZero ?? 28 }
        set { UserDefaults.standard.set(newValue, forKey: "note.fontSize") }
    }
    
    var cursorWidth: Double {
        get { UserDefaults.standard.double(forKey: "note.cursorWidth").nonZero ?? 2 }
        set { UserDefaults.standard.set(newValue, forKey: "note.cursorWidth") }
    }
    
    var cursorBlinkEnabled: Bool {
        get { UserDefaults.standard.object(forKey: "note.cursorBlinkEnabled") as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: "note.cursorBlinkEnabled") }
    }
    
    var cursorAnimationEnabled: Bool {
        get { UserDefaults.standard.object(forKey: "note.cursorAnimationEnabled") as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: "note.cursorAnimationEnabled") }
    }
    
    var cursorAnimationDuration: Double {
        get { UserDefaults.standard.double(forKey: "note.cursorAnimationDuration").nonZero ?? 0.15 }
        set { UserDefaults.standard.set(newValue, forKey: "note.cursorAnimationDuration") }
    }
    
    var autocompleteEnabled: Bool {
        get { UserDefaults.standard.object(forKey: "note.autocompleteEnabled") as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: "note.autocompleteEnabled") }
    }
    
    var autocompleteDelay: Double {
        get { UserDefaults.standard.double(forKey: "note.autocompleteDelay") }
        set { UserDefaults.standard.set(newValue, forKey: "note.autocompleteDelay") }
    }
    
    var autocompleteOpacity: Double {
        get { UserDefaults.standard.double(forKey: "note.autocompleteOpacity").nonZero ?? 0.5 }
        set { UserDefaults.standard.set(newValue, forKey: "note.autocompleteOpacity") }
    }
    
    var suggestionMode: String {
        get { UserDefaults.standard.string(forKey: "note.suggestionMode") ?? "word" }
        set { UserDefaults.standard.set(newValue, forKey: "note.suggestionMode") }
    }
    
    var markdownRenderEnabled: Bool {
        get { UserDefaults.standard.object(forKey: "note.markdownRenderEnabled") as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: "note.markdownRenderEnabled") }
    }
    
    var sortOptionRaw: String {
        get { UserDefaults.standard.string(forKey: "note.sortOption") ?? NoteSortOption.dateNewest.rawValue }
        set { UserDefaults.standard.set(newValue, forKey: "note.sortOption") }
    }
    
    var doubleTapNavigationEnabled: Bool {
        get { UserDefaults.standard.object(forKey: "note.doubleTapNavigationEnabled") as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: "note.doubleTapNavigationEnabled") }
    }
    
    var doubleTapDelay: Double {
        get { UserDefaults.standard.double(forKey: "note.doubleTapDelay").nonZero ?? 200 }
        set { UserDefaults.standard.set(newValue, forKey: "note.doubleTapDelay") }
    }
    
    // MARK: - Computed Properties
    
    var sortOption: NoteSortOption {
        get { NoteSortOption(rawValue: sortOptionRaw) ?? .dateNewest }
        set { sortOptionRaw = newValue.rawValue }
    }
    
    var isEditingExternalFile: Bool {
        externalFileURL != nil
    }
    
    var selectedFolder: NoteFolder? {
        guard let selectedFolderID = selectedFolderID else { return nil }
        return getFolder(folderID: selectedFolderID)
    }
    
    var selectedNote: NoteItem? {
        guard let folder = selectedFolder,
              let selectedNoteID = selectedNoteID else { return nil }
        return folder.notes.first { $0.id == selectedNoteID }
    }
    
    var selectedNoteIndex: Int? {
        guard let folder = selectedFolder,
              let selectedNoteID = selectedNoteID else { return nil }
        return folder.notes.firstIndex { $0.id == selectedNoteID }
    }
    
    var selectedNoteTitle: String {
        if let url = externalFileURL {
            return url.lastPathComponent
        }
        return selectedNote?.title ?? "Select a note"
    }
    
    var activeText: String {
        isEditingExternalFile ? externalFileText : (selectedNote?.text ?? "")
    }
    
    var wordCount: Int {
        activeText
            .split(whereSeparator: { $0.isWhitespace || $0.isNewline })
            .count
    }
    
    var lineCount: Int {
        guard !activeText.isEmpty else { return 1 }
        return activeText.components(separatedBy: .newlines).count
    }
    
    var characterCount: Int {
        activeText.replacingOccurrences(of: "\n", with: "").count
    }
    
    var fontDesign: Font.Design {
        switch fontFamily {
        case "rounded": return .rounded
        case "serif": return .serif
        default: return .monospaced
        }
    }
    
    // MARK: - Text Bindings
    
    var activeTextBinding: Binding<String> {
        if isEditingExternalFile {
            return Binding(
                get: { [weak self] in self?.externalFileText ?? "" },
                set: { [weak self] newValue in
                    self?.externalFileText = newValue
                    self?.saveExternalFile()
                }
            )
        } else {
            return selectedNoteTextBinding
        }
    }
    
    var selectedNoteTextBinding: Binding<String> {
        Binding(
            get: { [weak self] in
                self?.selectedNote?.text ?? ""
            },
            set: { [weak self] newValue in
                guard let self = self,
                      let selectedFolderID = self.selectedFolderID,
                      let selectedNoteID = self.selectedNoteID else { return }
                
                self.updateFolder(folderID: selectedFolderID) { folder in
                    guard let noteIndex = folder.notes.firstIndex(where: { $0.id == selectedNoteID }) else { return }
                    folder.notes[noteIndex].text = newValue
                    folder.notes[noteIndex].updatedAt = Date()
                    let trimmed = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !trimmed.isEmpty {
                        if folder.notes[noteIndex].isTitleCustom == false {
                            let baseTitle = self.firstLineTitle(from: trimmed)
                            let uniqueTitle = self.uniqueNoteTitle(baseTitle, in: folder.notes, excludingNoteID: selectedNoteID)
                            folder.notes[noteIndex].title = uniqueTitle
                        }
                    }
                }
                self.saveAllToDisk()
            }
        )
    }
    
    // MARK: - Initialization
    
    init() {
        // Set default for isDarkMode if not set
        if UserDefaults.standard.object(forKey: "note.isDarkMode") == nil {
            UserDefaults.standard.set(true, forKey: "note.isDarkMode")
        }
    }
    
    // MARK: - Data Loading
    
    func loadFromVault() {
        folders = vaultManager.loadFolders()
        print("📂 Loaded \(folders.count) folders from vault")
    }
    
    func saveAllToDisk() {
        folders = vaultManager.saveFolders(folders)
    }
    
    func refreshTrash() {
        trashItems = vaultManager.scanTrash(currentFolders: folders)
    }
    
    func ensureInitialSelection() {
        if folders.isEmpty {
            let defaultFolder = NoteFolder(name: "Notes")
            folders.append(defaultFolder)
            saveAllToDisk()
        }
        
        if selectedFolderID == nil {
            selectedFolderID = firstFolderID(in: folders)
        }
        if selectedNoteID == nil,
           let selectedFolderID = selectedFolderID,
           let folder = getFolder(folderID: selectedFolderID) {
            selectedNoteID = folder.notes.first?.id
        }
    }
    
    // MARK: - External File Handling
    
    func closeExternalFile() {
        saveExternalFile()
        externalFileURL = nil
        externalFileText = ""
    }
    
    func saveExternalFile() {
        guard let url = externalFileURL else { return }
        do {
            try externalFileText.write(to: url, atomically: true, encoding: .utf8)
            print("💾 Saved external file: \(url.path)")
        } catch {
            print("❌ Failed to save external file: \(error)")
        }
    }
    
    func openExternalFile(url: URL) {
        if selectedNoteID != nil {
            saveAllToDisk()
        }
        
        if externalFileURL != nil {
            saveExternalFile()
        }
        
        selectedNoteID = nil
        
        do {
            let accessing = url.startAccessingSecurityScopedResource()
            defer {
                if accessing {
                    url.stopAccessingSecurityScopedResource()
                }
            }
            
            externalFileText = try String(contentsOf: url, encoding: .utf8)
            externalFileURL = url
            print("📂 Opened external file: \(url.path)")
        } catch {
            print("❌ Failed to open external file: \(error)")
        }
    }
    
    func formatFilePath(_ url: URL) -> String {
        let path = url.path
        let homeDir = FileManager.default.homeDirectoryForCurrentUser.path
        
        if path.hasPrefix(homeDir) {
            return "~" + path.dropFirst(homeDir.count)
        }
        return path
    }
    
    func handleDroppedFiles(_ providers: [NSItemProvider]) -> Bool {
        let supportedExtensions: Set<String> = [
            "md", "markdown", "txt", "text",
            "html", "htm", "css", "js", "ts", "jsx", "tsx", "json", "xml",
            "swift", "m", "h", "c", "cpp", "cc", "cxx", "hpp", "java", "kt", "kts",
            "py", "rb", "php", "go", "rs", "scala", "clj", "ex", "exs",
            "sh", "bash", "zsh", "fish", "ps1", "bat", "cmd",
            "yaml", "yml", "toml", "ini", "conf", "cfg", "env",
            "csv", "sql", "graphql", "gql",
            "rst", "adoc", "tex", "log",
            "gitignore", "dockerfile", "makefile", "r", "lua", "vim", "el"
        ]
        
        for provider in providers {
            if provider.hasItemConformingToTypeIdentifier("public.file-url") {
                provider.loadItem(forTypeIdentifier: "public.file-url", options: nil) { [weak self] item, error in
                    if let data = item as? Data,
                       let url = URL(dataRepresentation: data, relativeTo: nil) {
                        let ext = url.pathExtension.lowercased()
                        let filename = url.lastPathComponent.lowercased()
                        
                        let isSupported = supportedExtensions.contains(ext) ||
                            supportedExtensions.contains(filename) ||
                            ext.isEmpty && !filename.hasPrefix(".") == false
                        
                        if isSupported {
                            DispatchQueue.main.async {
                                self?.openExternalFile(url: url)
                            }
                        }
                    }
                }
                return true
            }
        }
        return false
    }
    
    // MARK: - Search Navigation
    
    func navigateToNextMatch() {
        guard searchMatchCount > 0 else { return }
        currentSearchIndex = (currentSearchIndex + 1) % searchMatchCount
        triggerHaptic()
    }
    
    func navigateToPreviousMatch() {
        guard searchMatchCount > 0 else { return }
        currentSearchIndex = (currentSearchIndex - 1 + searchMatchCount) % searchMatchCount
        triggerHaptic()
    }
    
    func closeSearch() {
        searchText = ""
        replaceText = ""
        showReplaceMode = false
        showReplacePopover = false
        currentSearchIndex = 0
        searchMatchCount = 0
    }
    
    func updateSearchMatches(count: Int, isComplete: Bool) {
        searchMatchCount = count
        isSearchComplete = isComplete
        if currentSearchIndex >= count {
            currentSearchIndex = max(0, count - 1)
        }
    }
    
    func replaceCurrentMatch() {
        guard let selectedNoteIndex = selectedNoteIndex,
              let selectedFolderID = selectedFolderID,
              !searchText.isEmpty else { return }
        
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        
        updateFolder(folderID: selectedFolderID) { folder in
            let currentText = folder.notes[selectedNoteIndex].text
            
            let matches = self.findMatches(in: currentText, query: query)
            guard self.currentSearchIndex < matches.count else { return }
            
            let match = matches[self.currentSearchIndex]
            let beforeMatch = currentText[currentText.startIndex..<match.lowerBound]
            let afterMatch = currentText[match.upperBound..<currentText.endIndex]
            
            folder.notes[selectedNoteIndex].text = String(beforeMatch) + self.replaceText + String(afterMatch)
            folder.notes[selectedNoteIndex].updatedAt = Date()
        }
        
        saveAllToDisk()
        
        #if os(macOS)
        triggerHaptic(.generic)
        #else
        triggerHaptic(.light)
        #endif
    }
    
    func replaceAll() {
        guard let selectedNoteIndex = selectedNoteIndex,
              let selectedFolderID = selectedFolderID,
              !searchText.isEmpty else { return }
        
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        
        updateFolder(folderID: selectedFolderID) { folder in
            let currentText = folder.notes[selectedNoteIndex].text
            
            folder.notes[selectedNoteIndex].text = currentText.replacingOccurrences(
                of: query,
                with: self.replaceText,
                options: .caseInsensitive
            )
            folder.notes[selectedNoteIndex].updatedAt = Date()
        }
        
        saveAllToDisk()
        
        #if os(macOS)
        triggerHaptic(.generic)
        #else
        triggerHaptic(.medium)
        #endif
    }
    
    func findMatches(in text: String, query: String) -> [Range<String.Index>] {
        var matches: [Range<String.Index>] = []
        var searchRange = text.startIndex..<text.endIndex
        
        while let range = text.range(of: query, options: .caseInsensitive, range: searchRange) {
            matches.append(range)
            searchRange = range.upperBound..<text.endIndex
        }
        
        return matches
    }
    
    // MARK: - Folder Operations
    
    func addFolder(atRoot: Bool) {
        let baseName = "New Folder"
        let targetList: [NoteFolder]
        
        if atRoot || selectedFolderID == nil {
            targetList = folders
        } else if let parentID = selectedFolderID {
            targetList = getChildrenFolders(parentFolderID: parentID)
        } else {
            targetList = folders
        }
        
        let uniqueName = uniqueFolderName(baseName, in: targetList)
        let newFolder = NoteFolder(name: uniqueName)
        
        if atRoot || selectedFolderID == nil {
            folders.insert(newFolder, at: 0)
        } else if let selectedFolderID = selectedFolderID {
            _ = insertSubfolder(in: &folders, parentFolderID: selectedFolderID, subfolder: newFolder)
        }
        selectedFolderID = newFolder.id
        selectedNoteID = nil
        saveAllToDisk()
        startRenameFolder(folderID: newFolder.id)
    }
    
    func addSubfolder(parentFolderID: NoteFolder.ID) {
        let baseName = "New Folder"
        let targetList = getChildrenFolders(parentFolderID: parentFolderID)
        let uniqueName = uniqueFolderName(baseName, in: targetList)
        let newFolder = NoteFolder(name: uniqueName)
        
        _ = insertSubfolder(in: &folders, parentFolderID: parentFolderID, subfolder: newFolder)
        selectedFolderID = newFolder.id
        selectedNoteID = nil
        saveAllToDisk()
        startRenameFolder(folderID: newFolder.id)
    }
    
    func deleteSelectedFolder() {
        guard let selectedFolderID = selectedFolderID else { return }
        deleteFolder(folderID: selectedFolderID)
    }
    
    func deleteFolder(folderID: NoteFolder.ID) {
        let wasSelected = (selectedFolderID == folderID)
        _ = removeFolder(in: &folders, folderID: folderID)
        saveAllToDisk()
        refreshTrash()
        
        if wasSelected {
            selectedFolderID = firstFolderID(in: folders)
            if let folderID = selectedFolderID, let folder = getFolder(folderID: folderID) {
                selectedNoteID = folder.notes.first?.id
            } else {
                selectedNoteID = nil
            }
        }
    }
    
    // MARK: - Note Operations
    
    func addNote() {
        guard let selectedFolderID = selectedFolderID,
              let folder = getFolder(folderID: selectedFolderID) else { return }
        
        let baseName = "New Note"
        let uniqueName = uniqueNoteTitle(baseName, in: folder.notes)
        let newNote = NoteItem(title: uniqueName, text: "", savedTitle: uniqueName)
        
        updateFolder(folderID: selectedFolderID) { folder in
            folder.notes.insert(newNote, at: 0)
        }
        selectedNoteID = newNote.id
        saveAllToDisk()
    }
    
    func togglePinNote(noteID: NoteItem.ID) {
        guard let selectedFolderID = selectedFolderID else { return }
        
        updateFolder(folderID: selectedFolderID) { folder in
            guard let noteIndex = folder.notes.firstIndex(where: { $0.id == noteID }) else { return }
            folder.notes[noteIndex].isPinned.toggle()
        }
        saveAllToDisk()
        
        #if os(macOS)
        triggerHaptic(.generic)
        #else
        triggerHaptic(.light)
        #endif
    }
    
    func deleteSelectedNote() {
        guard let selectedNoteID = selectedNoteID else { return }
        deleteNote(noteID: selectedNoteID)
    }
    
    func deleteNote(noteID: NoteItem.ID) {
        let wasSelected = (selectedNoteID == noteID)
        guard let selectedFolderID = selectedFolderID else { return }
        
        updateFolder(folderID: selectedFolderID) { folder in
            guard let noteIndex = folder.notes.firstIndex(where: { $0.id == noteID }) else { return }
            folder.notes.remove(at: noteIndex)
        }
        saveAllToDisk()
        refreshTrash()
        
        if wasSelected {
            if let folder = getFolder(folderID: selectedFolderID) {
                selectedNoteID = folder.notes.first?.id
            } else {
                selectedNoteID = nil
            }
        }
    }
    
    // MARK: - Rename Operations
    
    func startRenameSelectedNote() {
        guard let selectedNoteID = selectedNoteID else { return }
        startRenameNote(noteID: selectedNoteID)
    }
    
    func startRenameFolder(folderID: NoteFolder.ID) {
        guard let folder = getFolder(folderID: folderID) else { return }
        renameRequest = RenameRequest(
            kind: .folder(folderID),
            title: "Rename Folder",
            placeholder: "Folder name",
            initialText: folder.name
        )
    }
    
    func startRenameNote(noteID: NoteItem.ID) {
        guard let selectedFolderID = selectedFolderID,
              let folder = getFolder(folderID: selectedFolderID),
              let noteIndex = folder.notes.firstIndex(where: { $0.id == noteID }) else { return }
        renameRequest = RenameRequest(
            kind: .note(folderID: selectedFolderID, noteID: noteID),
            title: "Rename Note",
            placeholder: "Note title",
            initialText: folder.notes[noteIndex].title
        )
    }
    
    func applyRename(request: RenameRequest, newName: String) {
        let trimmed = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        
        switch request.kind {
        case .folder(let folderID):
            let siblings = getSiblingFolders(folderID: folderID)
            let finalName = uniqueFolderName(String(trimmed.prefix(60)), in: siblings, excludingFolderID: folderID)
            
            updateFolder(folderID: folderID) { folder in
                folder.name = finalName
            }
            saveAllToDisk()
            
        case .note(let folderID, let noteID):
            guard let folder = getFolder(folderID: folderID) else { return }
            let finalTitle = uniqueNoteTitle(String(trimmed.prefix(80)), in: folder.notes, excludingNoteID: noteID)
            
            updateFolder(folderID: folderID) { folder in
                guard let noteIndex = folder.notes.firstIndex(where: { $0.id == noteID }) else { return }
                folder.notes[noteIndex].title = finalTitle
                folder.notes[noteIndex].isTitleCustom = true
                folder.notes[noteIndex].updatedAt = Date()
            }
            saveAllToDisk()
        }
    }
    
    // MARK: - Filter & Sort
    
    func filteredNotes(in folder: NoteFolder) -> [NoteItem] {
        let notes = folder.notes
        let q = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        
        let filtered = q.isEmpty ? notes : notes.filter { note in
            note.title.localizedCaseInsensitiveContains(q) || note.text.localizedCaseInsensitiveContains(q)
        }
        
        return filtered.sorted { note1, note2 in
            if note1.isPinned != note2.isPinned {
                return note1.isPinned
            }
            
            switch sortOption {
            case .nameAscending:
                return note1.title.localizedCaseInsensitiveCompare(note2.title) == .orderedAscending
            case .nameDescending:
                return note1.title.localizedCaseInsensitiveCompare(note2.title) == .orderedDescending
            case .dateNewest:
                return note1.updatedAt > note2.updatedAt
            case .dateOldest:
                return note1.updatedAt < note2.updatedAt
            case .createdNewest:
                return note1.createdAt > note2.createdAt
            case .createdOldest:
                return note1.createdAt < note2.createdAt
            }
        }
    }
    
    // MARK: - Text Processing Helpers
    
    func firstLineTitle(from text: String) -> String {
        let firstLine = text.split(whereSeparator: \.isNewline).first.map(String.init) ?? text
        let trimmed = firstLine.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return "Untitled" }
        
        let allowedCharacters = CharacterSet.alphanumerics
            .union(CharacterSet(charactersIn: " -_"))
        
        var sanitized = ""
        for character in trimmed {
            if allowedCharacters.contains(character.unicodeScalars.first!) {
                sanitized += String(character)
            }
        }
        
        sanitized = sanitized.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
        sanitized = sanitized.trimmingCharacters(in: .whitespacesAndNewlines)
        
        let result = sanitized.isEmpty ? "Untitled" : String(sanitized.prefix(60))
        return result
    }
    
    func notePreview(for text: String) -> String {
        let singleLine = text
            .replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return singleLine.isEmpty ? "" : singleLine
    }
    
    // MARK: - Folder Tree Navigation
    
    func firstFolderID(in folders: [NoteFolder]) -> NoteFolder.ID? {
        for folder in folders {
            return folder.id
        }
        return nil
    }
    
    func getFolder(folderID: NoteFolder.ID) -> NoteFolder? {
        func find(in list: [NoteFolder]) -> NoteFolder? {
            for folder in list {
                if folder.id == folderID { return folder }
                if let found = find(in: folder.children) { return found }
            }
            return nil
        }
        return find(in: folders)
    }
    
    func updateFolder(folderID: NoteFolder.ID, _ update: (inout NoteFolder) -> Void) {
        func walk(_ list: inout [NoteFolder]) -> Bool {
            for i in list.indices {
                if list[i].id == folderID {
                    update(&list[i])
                    return true
                }
                if walk(&list[i].children) {
                    return true
                }
            }
            return false
        }
        _ = walk(&folders)
    }
    
    func insertSubfolder(in folders: inout [NoteFolder], parentFolderID: NoteFolder.ID, subfolder: NoteFolder) -> Bool {
        for i in folders.indices {
            if folders[i].id == parentFolderID {
                folders[i].children.insert(subfolder, at: 0)
                return true
            }
            if insertSubfolder(in: &folders[i].children, parentFolderID: parentFolderID, subfolder: subfolder) {
                return true
            }
        }
        return false
    }
    
    func removeFolder(in folders: inout [NoteFolder], folderID: NoteFolder.ID) -> Bool {
        for i in folders.indices {
            if folders[i].id == folderID {
                folders.remove(at: i)
                return true
            }
            if removeFolder(in: &folders[i].children, folderID: folderID) {
                return true
            }
        }
        return false
    }
    
    func getSiblingFolders(folderID: NoteFolder.ID) -> [NoteFolder] {
        func findSiblings(in list: [NoteFolder]) -> [NoteFolder]? {
            if list.contains(where: { $0.id == folderID }) {
                return list
            }
            for folder in list {
                if let found = findSiblings(in: folder.children) {
                    return found
                }
            }
            return nil
        }
        return findSiblings(in: folders) ?? []
    }
    
    func getChildrenFolders(parentFolderID: NoteFolder.ID) -> [NoteFolder] {
        guard let parent = getFolder(folderID: parentFolderID) else { return [] }
        return parent.children
    }
    
    // MARK: - Uniqueness Helpers
    
    func folderNameExists(_ name: String, in folderList: [NoteFolder], excludingFolderID: NoteFolder.ID? = nil) -> Bool {
        return folderList.contains { folder in
            folder.name.lowercased() == name.lowercased() && folder.id != excludingFolderID
        }
    }
    
    func uniqueFolderName(_ baseName: String, in folderList: [NoteFolder], excludingFolderID: NoteFolder.ID? = nil) -> String {
        var name = baseName
        var counter = 1
        
        while folderNameExists(name, in: folderList, excludingFolderID: excludingFolderID) {
            counter += 1
            name = "\(baseName) \(counter)"
        }
        
        return name
    }
    
    func noteTitleExists(_ title: String, in noteList: [NoteItem], excludingNoteID: NoteItem.ID? = nil) -> Bool {
        return noteList.contains { note in
            note.title.lowercased() == title.lowercased() && note.id != excludingNoteID
        }
    }
    
    func uniqueNoteTitle(_ baseTitle: String, in noteList: [NoteItem], excludingNoteID: NoteItem.ID? = nil) -> String {
        var title = baseTitle
        var counter = 1
        
        while noteTitleExists(title, in: noteList, excludingNoteID: excludingNoteID) {
            counter += 1
            title = "\(baseTitle) \(counter)"
        }
        
        return title
    }
    
    // MARK: - Drag & Drop
    
    func isNoteID(_ id: UUID) -> Bool {
        func findInFolders(_ folders: [NoteFolder]) -> Bool {
            for folder in folders {
                if folder.notes.contains(where: { $0.id == id }) {
                    return true
                }
                if findInFolders(folder.children) {
                    return true
                }
            }
            return false
        }
        return findInFolders(folders)
    }
    
    func isFolderID(_ id: UUID) -> Bool {
        func findInFolders(_ folders: [NoteFolder]) -> Bool {
            for folder in folders {
                if folder.id == id {
                    return true
                }
                if findInFolders(folder.children) {
                    return true
                }
            }
            return false
        }
        return findInFolders(folders)
    }
    
    func isDescendant(folderID: UUID, ofFolderID parentID: UUID) -> Bool {
        guard let parent = getFolder(folderID: parentID) else { return false }
        
        func checkChildren(_ children: [NoteFolder]) -> Bool {
            for child in children {
                if child.id == folderID {
                    return true
                }
                if checkChildren(child.children) {
                    return true
                }
            }
            return false
        }
        
        return checkChildren(parent.children)
    }
    
    func findFolderContainingNote(noteID: UUID) -> NoteFolder? {
        func find(in folders: [NoteFolder]) -> NoteFolder? {
            for folder in folders {
                if folder.notes.contains(where: { $0.id == noteID }) {
                    return folder
                }
                if let found = find(in: folder.children) {
                    return found
                }
            }
            return nil
        }
        return find(in: folders)
    }
    
    func removeNoteFromCurrentFolder(noteID: UUID) -> NoteItem? {
        func remove(from folders: inout [NoteFolder]) -> NoteItem? {
            for i in folders.indices {
                if let noteIndex = folders[i].notes.firstIndex(where: { $0.id == noteID }) {
                    let note = folders[i].notes.remove(at: noteIndex)
                    return note
                }
                if let note = remove(from: &folders[i].children) {
                    return note
                }
            }
            return nil
        }
        return remove(from: &folders)
    }
    
    func addNoteToFolder(note: NoteItem, folderID: UUID) {
        updateFolder(folderID: folderID) { folder in
            folder.notes.insert(note, at: 0)
        }
    }
    
    func moveNote(noteID: UUID, toFolderID: UUID) {
        guard let sourceFolder = findFolderContainingNote(noteID: noteID) else {
            print("❌ Cannot find source folder for note")
            return
        }
        
        guard sourceFolder.id != toFolderID else {
            print("ℹ️ Note is already in target folder")
            return
        }
        
        guard let sourcePath = vaultManager.getFolderPath(folderID: sourceFolder.id, in: folders),
              let destPath = vaultManager.getFolderPath(folderID: toFolderID, in: folders) else {
            print("❌ Cannot find folder paths")
            return
        }
        
        guard let note = sourceFolder.notes.first(where: { $0.id == noteID }) else {
            print("❌ Cannot find note")
            return
        }
        
        let success = vaultManager.moveNoteFile(
            noteTitle: note.title,
            fromFolderNames: sourcePath,
            toFolderNames: destPath
        )
        
        guard success else {
            print("❌ Failed to move note file on disk")
            return
        }
        
        if let removedNote = removeNoteFromCurrentFolder(noteID: noteID) {
            addNoteToFolder(note: removedNote, folderID: toFolderID)
            
            if selectedNoteID == noteID {
                selectedFolderID = toFolderID
            }
            
            saveAllToDisk()
            print("✅ Moved note '\(note.title)' to new folder")
        }
    }
    
    func removeFolderFromParent(folderID: UUID) -> NoteFolder? {
        func remove(from folders: inout [NoteFolder]) -> NoteFolder? {
            for i in folders.indices {
                if folders[i].id == folderID {
                    return folders.remove(at: i)
                }
                if let folder = remove(from: &folders[i].children) {
                    return folder
                }
            }
            return nil
        }
        return remove(from: &folders)
    }
    
    func moveFolder(folderID: UUID, toParentFolderID: UUID?) {
        if let targetID = toParentFolderID, folderID == targetID {
            print("⚠️ Cannot move folder into itself")
            return
        }
        
        if let targetID = toParentFolderID, isDescendant(folderID: targetID, ofFolderID: folderID) {
            print("⚠️ Cannot move folder into its descendant")
            return
        }
        
        guard let folder = getFolder(folderID: folderID) else {
            print("❌ Cannot find folder to move")
            return
        }
        
        let sourceParentPath = vaultManager.getParentFolderPath(folderID: folderID, in: folders) ?? []
        
        let destParentPath: [String]
        if let targetID = toParentFolderID {
            guard let path = vaultManager.getFolderPath(folderID: targetID, in: folders) else {
                print("❌ Cannot find target folder path")
                return
            }
            destParentPath = path
        } else {
            destParentPath = []
        }
        
        if sourceParentPath == destParentPath {
            print("ℹ️ Folder is already at target location")
            return
        }
        
        let success = vaultManager.moveFolderOnDisk(
            folderName: folder.name,
            fromParentNames: sourceParentPath,
            toParentNames: destParentPath
        )
        
        guard success else {
            print("❌ Failed to move folder on disk")
            return
        }
        
        if let removedFolder = removeFolderFromParent(folderID: folderID) {
            if let targetID = toParentFolderID {
                updateFolder(folderID: targetID) { parent in
                    parent.children.insert(removedFolder, at: 0)
                }
            } else {
                folders.insert(removedFolder, at: 0)
            }
            
            saveAllToDisk()
            print("✅ Moved folder '\(folder.name)' to new location")
        }
    }
    
    func handleDropOnFolder(items: [UUID], targetFolderID: UUID) -> Bool {
        guard let itemID = items.first else { return false }
        
        if isNoteID(itemID) {
            moveNote(noteID: itemID, toFolderID: targetFolderID)
            return true
        } else if isFolderID(itemID) {
            moveFolder(folderID: itemID, toParentFolderID: targetFolderID)
            return true
        }
        
        return false
    }
    
    func handleDropOnRoot(items: [UUID]) -> Bool {
        guard let itemID = items.first else { return false }
        
        if isFolderID(itemID) {
            moveFolder(folderID: itemID, toParentFolderID: nil)
            return true
        }
        
        return false
    }
    
    // MARK: - Text Highlighting
    
    func highlightedText(_ text: String, searchText: String) -> Text {
        guard !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return Text(text)
        }
        
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        var result = Text("")
        var searchStartIndex = text.startIndex
        
        while searchStartIndex < text.endIndex {
            if let range = text.range(of: query, options: .caseInsensitive, range: searchStartIndex..<text.endIndex) {
                if searchStartIndex < range.lowerBound {
                    result = result + Text(String(text[searchStartIndex..<range.lowerBound]))
                }
                
                let match = String(text[range])
                result = result + Text(match).foregroundColor(.yellow)
                
                searchStartIndex = range.upperBound
            } else {
                result = result + Text(String(text[searchStartIndex..<text.endIndex]))
                break
            }
        }
        
        return result
    }
    
    // MARK: - Trash Operations
    
    func restoreTrashItem(_ item: TrashItem) {
        vaultManager.restoreTrashItem(item, into: &folders)
        refreshTrash()
        saveAllToDisk()
    }
    
    func deleteTrashItem(_ item: TrashItem) {
        vaultManager.deleteTrashItem(item)
        refreshTrash()
    }
    
    func emptyTrash() {
        vaultManager.emptyTrash(items: trashItems)
        trashItems = []
    }
}

// MARK: - Double Extension Helper

private extension Double {
    var nonZero: Double? {
        self == 0 ? nil : self
    }
}
