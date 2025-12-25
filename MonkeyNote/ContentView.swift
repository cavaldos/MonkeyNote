//
//  ContentView.swift
//  Note
//
//  Created by Nguyen Ngoc Khanh on 24/12/25.
//

import SwiftUI
import Combine

// MARK: - Main View

struct ContentView: View {
    @AppStorage("note.isDarkMode") private var isDarkMode: Bool = true
    @StateObject private var vaultManager = VaultManager()
    @State private var showSettings: Bool = false

    @State private var folders: [NoteFolder] = []

    @State private var selectedFolderID: NoteFolder.ID?
    @State private var selectedNoteID: NoteItem.ID?

    @State private var searchText: String = ""

    @State private var renameRequest: RenameRequest?
    
    // Trash
    @State private var trashItems: [TrashItem] = []
    @State private var showTrash: Bool = false
    
    // Debounce save
    @State private var saveTask: Task<Void, Never>?

    @AppStorage("note.fontFamily") private var fontFamily: String = "monospaced"
    @AppStorage("note.fontSize") private var fontSize: Double = 28
    @AppStorage("note.cursorWidth") private var cursorWidth: Double = 2
    @AppStorage("note.cursorBlinkEnabled") private var cursorBlinkEnabled: Bool = true
    @AppStorage("note.cursorAnimationEnabled") private var cursorAnimationEnabled: Bool = true
    @AppStorage("note.cursorAnimationDuration") private var cursorAnimationDuration: Double = 0.15

    private var selectedFolderPath: [Int]? {
        guard let selectedFolderID = selectedFolderID else { return nil }
        return findFolderPath(in: folders, folderID: selectedFolderID)
    }

    private var selectedNoteIndex: Int? {
        guard let selectedFolderID = selectedFolderID, let selectedNoteID = selectedNoteID else { return nil }
        guard let folder = getFolder(folderID: selectedFolderID) else { return nil }
        return folder.notes.firstIndex(where: { $0.id == selectedNoteID })
    }

    private var selectedNoteTitle: String {
        guard let selectedFolderID = selectedFolderID,
              let folder = getFolder(folderID: selectedFolderID),
              let noteIndex = selectedNoteIndex else {
            return "Select a note"
        }
        return folder.notes[noteIndex].title
    }

    private var selectedNoteTextBinding: Binding<String> {
        Binding(
            get: {
                guard let selectedFolderID = selectedFolderID,
                      let selectedNoteID = selectedNoteID,
                      let folder = getFolder(folderID: selectedFolderID),
                      let noteIndex = folder.notes.firstIndex(where: { $0.id == selectedNoteID }) else { return "" }
                return folder.notes[noteIndex].text
            },
            set: { newValue in
                guard let selectedFolderID = selectedFolderID, let selectedNoteID = selectedNoteID else { return }
                
                // Update in-memory immediately
                updateFolder(folderID: selectedFolderID) { folder in
                    guard let noteIndex = folder.notes.firstIndex(where: { $0.id == selectedNoteID }) else { return }
                    folder.notes[noteIndex].text = newValue
                    folder.notes[noteIndex].updatedAt = Date()
                    let trimmed = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !trimmed.isEmpty {
                        if folder.notes[noteIndex].isTitleCustom == false {
                            folder.notes[noteIndex].title = firstLineTitle(from: trimmed)
                        }
                    }
                }
                
                // Debounced save to disk (500ms delay)
                saveTask?.cancel()
                saveTask = Task {
                    try? await Task.sleep(nanoseconds: 500_000_000) // 500ms
                    guard !Task.isCancelled else { return }
                    
                    await MainActor.run {
                        saveAllToDisk()
                    }
                }
            }
        )
    }
    
    /// Save entire folder structure to disk and sync savedTitle back
    private func saveAllToDisk() {
        folders = vaultManager.saveFolders(folders)
    }

    private var selectedNoteText: String {
        selectedNoteTextBinding.wrappedValue
    }

    private var wordCount: Int {
        selectedNoteText
            .split(whereSeparator: { $0.isWhitespace || $0.isNewline })
            .count
    }

    // Rough reading time: 200 wpm → seconds
    private var estimatedSeconds: Int {
        guard wordCount > 0 else { return 0 }
        let seconds = (Double(wordCount) / 200.0) * 60.0
        return max(1, Int(ceil(seconds)))
    }

    var body: some View {
        NavigationSplitView {
            sidebar
        } content: {
            notesList
        } detail: {
            detailEditor
        }
        .task {
            vaultManager.createVaultIfNeeded()
            loadFromVault()
            ensureInitialSelection()
            refreshTrash()
        }
        .sheet(item: $renameRequest) { request in
            RenameSheet(
                title: request.title,
                placeholder: request.placeholder,
                initialText: request.initialText,
                onCancel: { renameRequest = nil },
                onSave: { newName in
                    applyRename(request: request, newName: newName)
                    renameRequest = nil
                }
            )
        }
        .sheet(isPresented: $showSettings) {
            SettingsView(vaultManager: vaultManager)
                .presentationDetents([.medium])
                .presentationDragIndicator(.visible)
        }
        .preferredColorScheme(isDarkMode ? .dark : .light)
        .onDisappear {
            // Save when view disappears
            saveAllToDisk()
        }
    }

    private var background: some View {
        Group {
            if isDarkMode {
                Color(red: 49.0 / 255.0, green: 49.0 / 255.0, blue: 49.0 / 255.0)
            } else {
                Color(red: 0.97, green: 0.97, blue: 0.97)
            }
        }
        .ignoresSafeArea()
    }

    private var header: some View {
        HStack(spacing: 8) {
            Text(selectedNoteTitle)
            Circle()
                .fill(Color.red)
                .frame(width: 6, height: 6)
        }
        .font(.system(.body, design: .monospaced))
        .foregroundStyle(isDarkMode ? .white.opacity(0.45) : .black.opacity(0.55))
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var editor: some View {
#if os(macOS) // pointer
        ThickCursorTextEditor(
            text: selectedNoteTextBinding,
            isDarkMode: isDarkMode,
            cursorWidth: cursorWidth,
            cursorBlinkEnabled: cursorBlinkEnabled,
            cursorAnimationEnabled: cursorAnimationEnabled,
            cursorAnimationDuration: cursorAnimationDuration,
            fontSize: fontSize,
            fontFamily: fontFamily,
            searchText: searchText
        )
        .overlay(alignment: .topLeading) {
            if selectedNoteText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Text("Write something…")
                    .font(.system(size: fontSize, weight: .regular, design: fontDesign))
                    .foregroundStyle(isDarkMode ? .white.opacity(0.25) : .black.opacity(0.25))
                    .padding(.top, 0)
                    .padding(.leading, 8)
                    .allowsHitTesting(false)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
#else
        TextEditor(text: selectedNoteTextBinding)
            .font(.system(size: fontSize, weight: .regular, design: fontDesign))
            .foregroundStyle(isDarkMode ? .white.opacity(0.92) : .black.opacity(0.92))
            .scrollContentBackground(.hidden)
            .background(Color.clear)
            .overlay(alignment: .topLeading) {
                if selectedNoteText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Text("Write something…")
                        .font(.system(size: fontSize, weight: .regular, design: fontDesign))
                        .foregroundStyle(isDarkMode ? .white.opacity(0.25) : .black.opacity(0.25))
                        .padding(.top, 0)
                        .padding(.leading, 8)
                        .allowsHitTesting(false)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
#endif
    }

    private var statusBar: some View {
        HStack(spacing: 10) {
            Image(systemName: "doc.text")
                .font(.system(size: 12, weight: .regular))
            Text("\(wordCount) words")
            Text("|")
            Image(systemName: "clock")
                .font(.system(size: 12, weight: .regular))
            Text("\(estimatedSeconds) secs")
        }
        .font(.system(.footnote, design: .monospaced))
        .foregroundStyle(isDarkMode ? .white.opacity(0.45) : .black.opacity(0.55))
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(isDarkMode ? Color.white.opacity(0.06) : Color.black.opacity(0.06))
        )
    }

    private var sidebar: some View {
        ZStack {
            sidebarBackground

            VStack(spacing: 0) {
                List(selection: $selectedFolderID) {
                    // Folders section
                    Section("Folders") {
                        OutlineGroup(folders, children: \.outlineChildren) { folder in
                            HStack {
                                Label(folder.name, systemImage: "folder")
                                Spacer()
                                Text("\(folder.notes.count)")
                                    .foregroundStyle(.secondary)
                            }
                            .tag(folder.id)
                            .contextMenu {
                                Button {
                                    addSubfolder(parentFolderID: folder.id)
                                } label: {
                                    Text("New Folder")
                                }

                                Button {
                                    startRenameFolder(folderID: folder.id)
                                } label: {
                                    Text("Rename Folder")
                                }

                                Button(role: .destructive) {
                                    deleteFolder(folderID: folder.id)
                                } label: {
                                    Text("Delete Folder")
                                }
                            }
                        }
                    }
                    
                    // Trash section
                    Section("Trash") {
                        Button {
                            showTrash = true
                            refreshTrash()
                        } label: {
                            HStack {
                                Label("Trash", systemImage: "trash")
                                Spacer()
                                if !trashItems.isEmpty {
                                    Text("\(trashItems.count)")
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
                .listStyle(.sidebar)
                .scrollContentBackground(.hidden)

                HStack(spacing: 12) {
                    Button {
                        addFolder(atRoot: true)
                    } label: {
                        Image(systemName: "folder.badge.plus")
                    }

                    Button {
                        showSettings = true
                    } label: {
                        Image(systemName: "gear")
                    }
                }
                .padding(16)
            }
        }
        .navigationTitle("Folders")
        .sheet(isPresented: $showTrash) {
            TrashView(
                trashItems: $trashItems,
                onRestore: { item in
                    vaultManager.restoreTrashItem(item, into: &folders)
                    refreshTrash()
                    saveAllToDisk()
                },
                onDelete: { item in
                    vaultManager.deleteTrashItem(item)
                    refreshTrash()
                },
                onEmptyTrash: {
                    vaultManager.emptyTrash(items: trashItems)
                    trashItems = []
                }
            )
            .frame(minWidth: 700, minHeight: 500)
        }
    }
    
    private func refreshTrash() {
        trashItems = vaultManager.scanTrash(currentFolders: folders)
    }

    private var notesList: some View {
        ZStack {
            background

            if let folderID = selectedFolderID, let folder = getFolder(folderID: folderID) {
                List(selection: $selectedNoteID) {
                    ForEach(filteredNotes(in: folder)) { note in
                        VStack(alignment: .leading, spacing: 4) {
                            highlightedText(note.title, searchText: searchText)
                                .font(.system(.body, design: .monospaced))
                                .lineLimit(1)
                            highlightedText(notePreview(for: note.text), searchText: searchText)
                                .font(.system(.footnote, design: .monospaced))
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                        .padding(.vertical, 4)
                        .tag(note.id)
                        .contextMenu {
                            Button {
                                startRenameNote(noteID: note.id)
                            } label: {
                                Text("Rename Note")
                            }

                            Button(role: .destructive) {
                                deleteNote(noteID: note.id)
                            } label: {
                                Text("Delete Note")
                            }
                        }
                    }
                }
                .scrollContentBackground(.hidden)
            } else {
                Text("Choose a folder")
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle(selectedFolderID == nil ? "Notes" : (getFolder(folderID: selectedFolderID!)?.name ?? "Notes"))
        .searchable(text: $searchText, placement: .toolbar, prompt: "Search")
        .toolbar {
            ToolbarItemGroup {
                Button {
                    addNote()
                } label: {
                    Image(systemName: "square.and.pencil")
                }
                .disabled(selectedFolderID == nil)

                Button {
                    startRenameSelectedNote()
                } label: {
                    Image(systemName: "pencil")
                }
                .disabled(selectedNoteID == nil)

                Button(role: .destructive) {
                    deleteSelectedNote()
                } label: {
                    Image(systemName: "trash")
                }
                .disabled(selectedNoteID == nil)
            }
        }
    }

    private var detailEditor: some View {
        ZStack {
            background

            if selectedNoteIndex == nil {
                Text("Select a note")
                    .foregroundStyle(isDarkMode ? .white.opacity(0.45) : .black.opacity(0.55))
            } else {
                VStack(spacing: 0) {
                    header
                        .padding(.top, 18)
                        .padding(.horizontal, 18)

                    editor
                        .padding(.top, 28)
                        .padding(.horizontal, 46)
                        .background(
                            RoundedRectangle(cornerRadius: 1, style: .continuous)
                                .fill(isDarkMode ? Color.black.opacity(0.16) : Color.black.opacity(0.04))
                        )

                    Spacer(minLength: 0)

                    statusBar
                        .padding(.bottom, 18)
                }
            }
        }
    }

    private var sidebarBackground: some View {
#if os(macOS)
        VisualEffectBlur(material: .sidebar, blendingMode: .behindWindow)
            .overlay(
                (isDarkMode ? Color.black.opacity(0.10) : Color.white.opacity(0.10))
            )
            .ignoresSafeArea()
#else
        background
#endif
    }

    private func ensureInitialSelection() {
        if folders.isEmpty {
            // Create default folder if none exists
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

    private func addFolder(atRoot: Bool) {
        let newFolder = NoteFolder(name: "New Folder")
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

    private func addSubfolder(parentFolderID: NoteFolder.ID) {
        let newFolder = NoteFolder(name: "New Folder")
        _ = insertSubfolder(in: &folders, parentFolderID: parentFolderID, subfolder: newFolder)
        selectedFolderID = newFolder.id
        selectedNoteID = nil
        saveAllToDisk()
        startRenameFolder(folderID: newFolder.id)
    }

    private func deleteSelectedFolder() {
        guard let selectedFolderID = selectedFolderID else { return }
        deleteFolder(folderID: selectedFolderID)
    }

    private func deleteFolder(folderID: NoteFolder.ID) {
        let wasSelected = (selectedFolderID == folderID)
        _ = removeFolder(in: &folders, folderID: folderID)
        saveAllToDisk()

        if wasSelected {
            selectedFolderID = firstFolderID(in: folders)
            if let folderID = selectedFolderID, let folder = getFolder(folderID: folderID) {
                selectedNoteID = folder.notes.first?.id
            } else {
                selectedNoteID = nil
            }
        }
    }

    private func addNote() {
        guard let selectedFolderID = selectedFolderID else { return }
        let newNote = NoteItem(title: "New Note", text: "", savedTitle: "New Note")
        updateFolder(folderID: selectedFolderID) { folder in
            folder.notes.insert(newNote, at: 0)
        }
        selectedNoteID = newNote.id
        saveAllToDisk()
    }

    private func deleteSelectedNote() {
        guard let selectedNoteID = selectedNoteID else { return }
        deleteNote(noteID: selectedNoteID)
    }

    private func deleteNote(noteID: NoteItem.ID) {
        let wasSelected = (selectedNoteID == noteID)
        guard let selectedFolderID = selectedFolderID else { return }
        
        updateFolder(folderID: selectedFolderID) { folder in
            guard let noteIndex = folder.notes.firstIndex(where: { $0.id == noteID }) else { return }
            folder.notes.remove(at: noteIndex)
        }
        saveAllToDisk()

        if wasSelected {
            if let folder = getFolder(folderID: selectedFolderID) {
                selectedNoteID = folder.notes.first?.id
            } else {
                selectedNoteID = nil
            }
        }
    }

    private func filteredNotes(in folder: NoteFolder) -> [NoteItem] {
        let notes = folder.notes
        let q = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return notes }

        return notes.filter { note in
            note.title.localizedCaseInsensitiveContains(q) || note.text.localizedCaseInsensitiveContains(q)
        }
    }

    private func startRenameSelectedNote() {
        guard let selectedNoteID = selectedNoteID else { return }
        startRenameNote(noteID: selectedNoteID)
    }

    private func startRenameFolder(folderID: NoteFolder.ID) {
        guard let folder = getFolder(folderID: folderID) else { return }
        renameRequest = RenameRequest(
            kind: .folder(folderID),
            title: "Rename Folder",
            placeholder: "Folder name",
            initialText: folder.name
        )
    }

    private func startRenameNote(noteID: NoteItem.ID) {
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

    private func applyRename(request: RenameRequest, newName: String) {
        let trimmed = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        switch request.kind {
        case .folder(let folderID):
            updateFolder(folderID: folderID) { folder in
                folder.name = String(trimmed.prefix(60))
            }
            saveAllToDisk()

        case .note(let folderID, let noteID):
            updateFolder(folderID: folderID) { folder in
                guard let noteIndex = folder.notes.firstIndex(where: { $0.id == noteID }) else { return }
                folder.notes[noteIndex].title = String(trimmed.prefix(80))
                folder.notes[noteIndex].isTitleCustom = true
                folder.notes[noteIndex].updatedAt = Date()
            }
            saveAllToDisk()
        }
    }

    private func firstLineTitle(from text: String) -> String {
        let firstLine = text.split(whereSeparator: \.isNewline).first.map(String.init) ?? text
        let trimmed = firstLine.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return "Untitled" }
        
        // Loại bỏ các ký tự đặc biệt, chỉ giữ lại chữ, số, khoảng trắng, gạch nối và gạch dưới
        let allowedCharacters = CharacterSet.alphanumerics
            .union(CharacterSet(charactersIn: " -_"))
        
        var sanitized = ""
        for character in trimmed {
            if allowedCharacters.contains(character.unicodeScalars.first!) {
                sanitized += String(character)
            }
        }
        
        // Thay thế nhiều khoảng trắng liên tiếp bằng một khoảng trắng
        sanitized = sanitized.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
        
        // Xóa khoảng trắng ở đầu và cuối
        sanitized = sanitized.trimmingCharacters(in: .whitespacesAndNewlines)
        
        let result = sanitized.isEmpty ? "Untitled" : String(sanitized.prefix(60))
        return result
    }

    private func notePreview(for text: String) -> String {
        let singleLine = text
            .replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return singleLine.isEmpty ? "" : singleLine
    }

    private func firstFolderID(in folders: [NoteFolder]) -> NoteFolder.ID? {
        for folder in folders {
            return folder.id
        }
        return nil
    }

    private func findFolderPath(in folders: [NoteFolder], folderID: NoteFolder.ID, current: [Int] = []) -> [Int]? {
        for (idx, folder) in folders.enumerated() {
            if folder.id == folderID {
                return current + [idx]
            }
            if let found = findFolderPath(in: folder.children, folderID: folderID, current: current + [idx]) {
                return found
            }
        }
        return nil
    }

    private func getFolder(folderID: NoteFolder.ID) -> NoteFolder? {
        func find(in list: [NoteFolder]) -> NoteFolder? {
            for folder in list {
                if folder.id == folderID { return folder }
                if let found = find(in: folder.children) { return found }
            }
            return nil
        }
        return find(in: folders)
    }

    private func getFolder(at path: [Int]) -> NoteFolder? {
        guard let first = path.first else { return nil }
        guard folders.indices.contains(first) else { return nil }
        var currentFolder = folders[first]
        if path.count == 1 { return currentFolder }

        for idx in path.dropFirst() {
            guard currentFolder.children.indices.contains(idx) else { return nil }
            currentFolder = currentFolder.children[idx]
        }
        return currentFolder
    }

    private func updateFolder(folderID: NoteFolder.ID, _ update: (inout NoteFolder) -> Void) {
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

    private func insertSubfolder(in folders: inout [NoteFolder], parentFolderID: NoteFolder.ID, subfolder: NoteFolder) -> Bool {
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

    private func removeFolder(in folders: inout [NoteFolder], folderID: NoteFolder.ID) -> Bool {
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

    private var fontDesign: Font.Design {
        switch fontFamily {
        case "rounded": return .rounded
        case "serif": return .serif
        default: return .monospaced
        }
    }

    private var customFont: Font? {
        #if os(macOS)
        return Font.custom(fontFamily, size: fontSize)
        #else
        return Font.custom(fontFamily, size: fontSize)
        #endif
    }

    private func highlightedText(_ text: String, searchText: String) -> Text {
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
    
    /// Load folder structure from vault
    private func loadFromVault() {
        folders = vaultManager.loadFolders()
        print("📂 Loaded \(folders.count) folders from vault")
    }
}

// MARK: - Preview

#Preview {
    ContentView()
}
