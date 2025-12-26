//
//  ContentView.swift
//  Note
//
//  Created by Nguyen Ngoc Khanh on 24/12/25.
//

import SwiftUI
import Combine

#if os(iOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif

// MARK: - Haptic Feedback Helper
#if os(iOS)
func triggerHaptic(_ style: UIImpactFeedbackGenerator.FeedbackStyle = .light) {
    let generator = UIImpactFeedbackGenerator(style: style)
    generator.impactOccurred()
}

func triggerNotificationHaptic(_ type: UINotificationFeedbackGenerator.FeedbackType) {
    let generator = UINotificationFeedbackGenerator()
    generator.notificationOccurred(type)
}

#elseif os(macOS)
func triggerHaptic(_ pattern: NSHapticFeedbackManager.FeedbackPattern = .generic) {
    NSHapticFeedbackManager.defaultPerformer.perform(pattern, performanceTime: .default)
}
#endif

// MARK: - Notifications
extension Notification.Name {
    static let focusSearch = Notification.Name("focusSearch")
    static let focusEditor = Notification.Name("focusEditor")
}

// MARK: - Focusable Search TextField
#if os(macOS)
struct FocusableSearchField: NSViewRepresentable {
    @Binding var text: String
    var onSubmit: (() -> Void)? = nil
    var onEscape: (() -> Void)? = nil
    
    func makeNSView(context: Context) -> NSTextField {
        let textField = NSTextField()
        textField.placeholderString = "Search"
        textField.isBordered = false
        textField.backgroundColor = .clear
        textField.font = .systemFont(ofSize: 12)
        textField.focusRingType = .none
        textField.delegate = context.coordinator
        
        NotificationCenter.default.addObserver(
            context.coordinator,
            selector: #selector(Coordinator.focusTextField),
            name: .focusSearch,
            object: nil
        )
        context.coordinator.textField = textField
        
        return textField
    }
    
    func updateNSView(_ nsView: NSTextField, context: Context) {
        if nsView.stringValue != text {
            nsView.stringValue = text
        }
        context.coordinator.onSubmit = onSubmit
        context.coordinator.onEscape = onEscape
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text, onSubmit: onSubmit, onEscape: onEscape)
    }
    
    class Coordinator: NSObject, NSTextFieldDelegate {
        @Binding var text: String
        weak var textField: NSTextField?
        var onSubmit: (() -> Void)?
        var onEscape: (() -> Void)?
        
        init(text: Binding<String>, onSubmit: (() -> Void)?, onEscape: (() -> Void)?) {
            _text = text
            self.onSubmit = onSubmit
            self.onEscape = onEscape
        }
        
        @objc func focusTextField() {
            DispatchQueue.main.async {
                self.textField?.window?.makeFirstResponder(self.textField)
            }
        }
        
        func controlTextDidChange(_ obj: Notification) {
            if let textField = obj.object as? NSTextField {
                text = textField.stringValue
            }
        }
        
        func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
            if commandSelector == #selector(NSResponder.insertNewline(_:)) {
                // Enter key pressed
                onSubmit?()
                return true
            } else if commandSelector == #selector(NSResponder.cancelOperation(_:)) {
                // ESC key pressed - unfocus and return focus to editor
                textField?.window?.makeFirstResponder(nil)
                onEscape?()
                // Post notification to focus editor
                NotificationCenter.default.post(name: .focusEditor, object: nil)
                return true
            }
            return false
        }
    }
}
#endif

// MARK: - Main View

struct ContentView: View {
    @AppStorage("note.isDarkMode") private var isDarkMode: Bool = true
    @StateObject private var vaultManager = VaultManager()
    @State private var showSettings: Bool = false

    @State private var folders: [NoteFolder] = []

    @State private var selectedFolderID: NoteFolder.ID?
    @State private var selectedNoteID: NoteItem.ID?

    @State private var searchText: String = ""
    
    // Search navigation state
    @State private var searchMatchCount: Int = 0
    @State private var currentSearchIndex: Int = 0

    @State private var renameRequest: RenameRequest?
    
    // Trash
    @State private var trashItems: [TrashItem] = []
    @State private var showTrash: Bool = false
    
    // Debounce save
    @State private var saveTask: Task<Void, Never>?
    
    // Drag & Drop state
    @State private var dragOverFolderID: NoteFolder.ID?
    
    // Hover state for folder menu
    @State private var hoverFolderID: NoteFolder.ID?
    
    // Search focus
    @FocusState private var isSearchFocused: Bool

    @AppStorage("note.fontFamily") private var fontFamily: String = "monospaced"
    @AppStorage("note.fontSize") private var fontSize: Double = 28
    @AppStorage("note.cursorWidth") private var cursorWidth: Double = 2
    @AppStorage("note.cursorBlinkEnabled") private var cursorBlinkEnabled: Bool = true
    @AppStorage("note.cursorAnimationEnabled") private var cursorAnimationEnabled: Bool = true
    @AppStorage("note.cursorAnimationDuration") private var cursorAnimationDuration: Double = 0.15
    @AppStorage("note.autocompleteEnabled") private var autocompleteEnabled: Bool = true
    @AppStorage("note.autocompleteDelay") private var autocompleteDelay: Double = 0.0
    @AppStorage("note.autocompleteOpacity") private var autocompleteOpacity: Double = 0.5
    @AppStorage("note.suggestionMode") private var suggestionMode: String = "word"
    @AppStorage("note.markdownRenderEnabled") private var markdownRenderEnabled: Bool = true

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

    // MARK: - Note Text Binding & Updates
    
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
                            let baseTitle = firstLineTitle(from: trimmed)
                            let uniqueTitle = uniqueNoteTitle(baseTitle, in: folder.notes, excludingNoteID: selectedNoteID)
                            folder.notes[noteIndex].title = uniqueTitle
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

    // MARK: - Statistics Calculations
    
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

    // MARK: - UI Components
    
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
            searchText: searchText,
            autocompleteEnabled: autocompleteEnabled,
            autocompleteDelay: autocompleteDelay,
            autocompleteOpacity: autocompleteOpacity,
            suggestionMode: suggestionMode,
            markdownRenderEnabled: markdownRenderEnabled,
            horizontalPadding: 46,
            currentSearchIndex: currentSearchIndex,
            onSearchMatchesChanged: { count in
                searchMatchCount = count
                // Reset index if it's out of bounds
                if currentSearchIndex >= count {
                    currentSearchIndex = max(0, count - 1)
                }
            }
        )
        .overlay(alignment: .topLeading) {
            if selectedNoteText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Text("Write something…")
                    .font(.system(size: fontSize, weight: .regular, design: fontDesign))
                    .foregroundStyle(isDarkMode ? .white.opacity(0.25) : .black.opacity(0.25))
                    .padding(.top, 0)
                    .padding(.leading, 46 + 8)  // horizontalPadding + extra
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
    
    // MARK: - Search Navigation Functions
    
    private func navigateToNextMatch() {
        guard searchMatchCount > 0 else { return }
        currentSearchIndex = (currentSearchIndex + 1) % searchMatchCount
        triggerHaptic() // Haptic feedback
    }
    
    private func navigateToPreviousMatch() {
        guard searchMatchCount > 0 else { return }
        currentSearchIndex = (currentSearchIndex - 1 + searchMatchCount) % searchMatchCount
        triggerHaptic() // Haptic feedback
    }
    
    private func closeSearch() {
        searchText = ""
        currentSearchIndex = 0
        searchMatchCount = 0
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

    // MARK: - Sidebar Navigation
    
    private var sidebar: some View {
        ZStack {
            sidebarBackground

            VStack(spacing: 0) {
                List(selection: $selectedFolderID) {
                    // Folders section
                    Section("Folders") {
                        OutlineGroup(folders, children: \.outlineChildren) { folder in
                            folderRow(folder: folder)
                        }
                    }
                    
                    // Drop zone for moving folder to root
                    Section {
                        HStack {
                            Image(systemName: "arrow.turn.up.left")
                                .foregroundStyle(.secondary)
                            Text("Move to Root")
                                .foregroundStyle(.secondary)
                            Spacer()
                        }
                        .padding(.vertical, 4)
                        .opacity(dragOverFolderID == nil ? 0.5 : 0.3)
                    }
                    .dropDestination(for: String.self) { items, location in
                        guard let itemString = items.first,
                              let itemID = UUID(uuidString: itemString) else { return false }
                        return handleDropOnRoot(items: [itemID])
                    } isTargeted: { isTargeted in
                        // Visual feedback when dragging over root drop zone
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
    
    // MARK: - Folder Display
    
    /// Folder row with drag & drop support
    @ViewBuilder
    private func folderRow(folder: NoteFolder) -> some View {
        HStack {
            Label(folder.name, systemImage: "folder")
            Spacer()
            
            // Menu button - only visible on hover
            if hoverFolderID == folder.id {
                Menu {
                    Button {
                        addSubfolder(parentFolderID: folder.id)
                    } label: {
                        Label("New Folder", systemImage: "folder.badge.plus")
                    }
                    
                    Button {
                        startRenameFolder(folderID: folder.id)
                    } label: {
                        Label("Rename Folder", systemImage: "pencil")
                    }
                    
                    Divider()
                    
                    Button(role: .destructive) {
                        deleteFolder(folderID: folder.id)
                    } label: {
                        Label("Delete Folder", systemImage: "trash")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle.fill")
                        .foregroundStyle(.gray)
                        .font(.system(size: 14))
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize()
            }
            
            Text("\(folder.notes.count)")
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 4)
                .fill(dragOverFolderID == folder.id ? Color.accentColor.opacity(0.5) : Color.clear)
        )
        .contentShape(Rectangle())
        .onHover { isHovering in
            withAnimation(.easeInOut(duration: 0.15)) {
                hoverFolderID = isHovering ? folder.id : nil
            }
        }
        .tag(folder.id)
        .draggable(folder.id.uuidString)
        .dropDestination(for: String.self) { items, location in
            dragOverFolderID = nil
            guard let itemString = items.first,
                  let itemID = UUID(uuidString: itemString) else { return false }
            return handleDropOnFolder(items: [itemID], targetFolderID: folder.id)
        } isTargeted: { isTargeted in
            withAnimation(.easeInOut(duration: 0.15)) {
                dragOverFolderID = isTargeted ? folder.id : nil
            }
        }
        .listRowInsets(EdgeInsets(top: 2, leading: 1, bottom: 2, trailing: 1))
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
    
    // MARK: - Notes List & Trash
    
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
                        .draggable(note.id.uuidString) // Drag note
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
                .clipped()
                .id(searchText)
            } else {
                Text("Choose a folder")
                    .foregroundStyle(.secondary)
            }
        }
        .clipped()
        .navigationTitle(selectedFolderID == nil ? "Notes" : (getFolder(folderID: selectedFolderID!)?.name ?? "Notes"))
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    addNote()
                } label: {
                    Image(systemName: "square.and.pencil")
                }
                .disabled(selectedFolderID == nil)
            }
        }
    }

    // MARK: - Detail Editor
    
    private var detailEditor: some View {
        ZStack {
            background
            (isDarkMode ? Color.black.opacity(0.16) : Color.black.opacity(0.04))
                .ignoresSafeArea()

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
                }
                .safeAreaInset(edge: .bottom) {
                    statusBar
                        .frame(maxWidth: .infinity)
                        .padding(.top, 2)
                        .padding(.bottom, 10)
                }
            }
        }
        .toolbar {
            ToolbarItem(placement: .principal) {
                Spacer()
            }
            ToolbarItemGroup(placement: .primaryAction) {
                // Markdown render toggle button
                Button {
                    markdownRenderEnabled.toggle()
                } label: {
                    Image(systemName: markdownRenderEnabled ? "text.badge.checkmark" : "text.badge.xmark")
                }
                .help(markdownRenderEnabled ? "Disable Markdown Rendering" : "Enable Markdown Rendering")
                
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
                
                // Search field with results and navigation && search results
                HStack(spacing: 6) {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(.secondary)
                        .font(.system(size: 11))
                    #if os(macOS)
                    FocusableSearchField(
                        text: $searchText,
                        onSubmit: { navigateToNextMatch() },
                        onEscape: { closeSearch() }
                    )
                    .frame(width: 120) // width search
                    #else
                    TextField("Search", text: $searchText)
                        .textFieldStyle(.plain)
                        .font(.system(size: 12))
                        .focused($isSearchFocused)
                    #endif
                    
                    // Show results and navigation when searching
                    if !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        // Hint text
                        Text("⏎")
                            .font(.system(size: 9))
                            .foregroundStyle(.secondary)
                            .transition(.opacity.combined(with: .scale(scale: 0.8)))// animation search text
                        
                        // Divider
                        Rectangle()
                            .fill(isDarkMode ? Color.white.opacity(0.2) : Color.black.opacity(0.15))
                            .frame(width: 1, height: 14)
                            .transition(.opacity.combined(with: .scale(scale: 0.8))) // animation search text
                        
                        // Results count
                        Text(searchMatchCount > 0 ? "\(currentSearchIndex + 1)/\(searchMatchCount)" : "0")
                            .font(.system(size: 10, weight: .medium, design: .monospaced))
                            .foregroundStyle(isDarkMode ? .white.opacity(0.7) : .black.opacity(0.7))
                            .transition(.opacity.combined(with: .scale(scale: 0.8))) // animation search text
                        
                        // Navigation buttons
                        Button {
                            navigateToPreviousMatch()
                        } label: {
                            Image(systemName: "chevron.up")
                                .font(.system(size: 9, weight: .semibold))
                                .frame(width: 18, height: 18)
                                .background(
                                    RoundedRectangle(cornerRadius: 3)
                                        .fill(isDarkMode ? Color.white.opacity(0.1) : Color.black.opacity(0.08))
                                )
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .disabled(searchMatchCount == 0)
                        .transition(.opacity.combined(with: .move(edge: .trailing))) // animation search text
                        
                        Button {
                            navigateToNextMatch()
                        } label: {
                            Image(systemName: "chevron.down")
                                .font(.system(size: 9, weight: .semibold))
                                .frame(width: 18, height: 18)
                                .background(
                                    RoundedRectangle(cornerRadius: 3)
                                        .fill(isDarkMode ? Color.white.opacity(0.1) : Color.black.opacity(0.08))
                                )
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .disabled(searchMatchCount == 0)
                        .transition(.opacity.combined(with: .move(edge: .trailing))) // animation search text
                        
                        // Close button
                        Button {
                            closeSearch()
                        } label: {
                            Image(systemName: "xmark")
                                .font(.system(size: 8, weight: .semibold))
                                .frame(width: 18, height: 18)
                                .background(
                                    RoundedRectangle(cornerRadius: 3)
                                        .fill(isDarkMode ? Color.white.opacity(0.1) : Color.black.opacity(0.08))
                                )
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .transition(.opacity.combined(with: .move(edge: .trailing))) // animation search text
                    }
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(isDarkMode ? Color.white.opacity(0.08) : Color.black.opacity(0.06))
                )
                .animation(.spring(response: 0.20, dampingFraction: 0.5), value: searchText.isEmpty)// animation search text
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

    // MARK: - Folder Operations (Create, Rename, Delete)
    
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

    private func addSubfolder(parentFolderID: NoteFolder.ID) {
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

    private func deleteSelectedFolder() {
        guard let selectedFolderID = selectedFolderID else { return }
        deleteFolder(folderID: selectedFolderID)
    }

    private func deleteFolder(folderID: NoteFolder.ID) {
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

    // MARK: - Note Operations (Create, Rename, Delete)
    
    private func addNote() {
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
        refreshTrash()

        if wasSelected {
            if let folder = getFolder(folderID: selectedFolderID) {
                selectedNoteID = folder.notes.first?.id
            } else {
                selectedNoteID = nil
            }
        }
    }

    // MARK: - Search & Filter
    
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
            // Check for duplicate name in siblings
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

    // MARK: - Text Processing Helpers
    
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

    // MARK: - Folder Tree Navigation Helpers
    
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
    
    /// Get sibling folders at the same level as the given folder
    private func getSiblingFolders(folderID: NoteFolder.ID) -> [NoteFolder] {
        func findSiblings(in list: [NoteFolder]) -> [NoteFolder]? {
            // Check if folder is at this level
            if list.contains(where: { $0.id == folderID }) {
                return list
            }
            // Search in children
            for folder in list {
                if let found = findSiblings(in: folder.children) {
                    return found
                }
            }
            return nil
        }
        return findSiblings(in: folders) ?? []
    }
    
    /// Get children folders of a parent folder
    private func getChildrenFolders(parentFolderID: NoteFolder.ID) -> [NoteFolder] {
        guard let parent = getFolder(folderID: parentFolderID) else { return [] }
        return parent.children
    }
    
    /// Check if a folder name already exists in a list of folders
    private func folderNameExists(_ name: String, in folderList: [NoteFolder], excludingFolderID: NoteFolder.ID? = nil) -> Bool {
        return folderList.contains { folder in
            folder.name.lowercased() == name.lowercased() && folder.id != excludingFolderID
        }
    }
    
    /// Generate a unique folder name by appending a number if needed
    private func uniqueFolderName(_ baseName: String, in folderList: [NoteFolder], excludingFolderID: NoteFolder.ID? = nil) -> String {
        var name = baseName
        var counter = 1
        
        while folderNameExists(name, in: folderList, excludingFolderID: excludingFolderID) {
            counter += 1
            name = "\(baseName) \(counter)"
        }
        
        return name
    }
    
    // MARK: - Note Title Uniqueness Helpers
    
    /// Check if a note title already exists in a list of notes
    private func noteTitleExists(_ title: String, in noteList: [NoteItem], excludingNoteID: NoteItem.ID? = nil) -> Bool {
        return noteList.contains { note in
            note.title.lowercased() == title.lowercased() && note.id != excludingNoteID
        }
    }
    
    /// Generate a unique note title by appending a number if needed
    private func uniqueNoteTitle(_ baseTitle: String, in noteList: [NoteItem], excludingNoteID: NoteItem.ID? = nil) -> String {
        var title = baseTitle
        var counter = 1
        
        while noteTitleExists(title, in: noteList, excludingNoteID: excludingNoteID) {
            counter += 1
            title = "\(baseTitle) \(counter)"
        }
        
        return title
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
    
    // MARK: - Drag & Drop Utilities
    
    /// Kiểm tra xem một UUID có thuộc về note không (không phải folder)
    private func isNoteID(_ id: UUID) -> Bool {
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
    
    /// Kiểm tra xem một UUID có thuộc về folder không
    private func isFolderID(_ id: UUID) -> Bool {
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
    
    /// Kiểm tra xem folder A có phải là con/cháu của folder B không (để tránh vòng lặp khi kéo thả)
    private func isDescendant(folderID: UUID, ofFolderID parentID: UUID) -> Bool {
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
    
    /// Tìm folder chứa note với ID cho trước
    private func findFolderContainingNote(noteID: UUID) -> NoteFolder? {
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
    
    /// Tìm và xóa note từ folder hiện tại, trả về note đã xóa
    private func removeNoteFromCurrentFolder(noteID: UUID) -> NoteItem? {
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
    
    /// Thêm note vào folder đích
    private func addNoteToFolder(note: NoteItem, folderID: UUID) {
        updateFolder(folderID: folderID) { folder in
            folder.notes.insert(note, at: 0)
        }
    }
    
    /// Di chuyển note từ folder này sang folder khác
    private func moveNote(noteID: UUID, toFolderID: UUID) {
        // Tìm folder nguồn
        guard let sourceFolder = findFolderContainingNote(noteID: noteID) else {
            print("❌ Cannot find source folder for note")
            return
        }
        
        // Không di chuyển nếu đã ở folder đích
        guard sourceFolder.id != toFolderID else {
            print("ℹ️ Note is already in target folder")
            return
        }
        
        // Lấy đường dẫn folder nguồn và đích
        guard let sourcePath = vaultManager.getFolderPath(folderID: sourceFolder.id, in: folders),
              let destPath = vaultManager.getFolderPath(folderID: toFolderID, in: folders) else {
            print("❌ Cannot find folder paths")
            return
        }
        
        // Tìm note để lấy title
        guard let note = sourceFolder.notes.first(where: { $0.id == noteID }) else {
            print("❌ Cannot find note")
            return
        }
        
        // Di chuyển file trên disk trước
        let success = vaultManager.moveNoteFile(
            noteTitle: note.title,
            fromFolderNames: sourcePath,
            toFolderNames: destPath
        )
        
        guard success else {
            print("❌ Failed to move note file on disk")
            return
        }
        
        // Cập nhật in-memory: xóa note từ folder cũ, thêm vào folder mới
        if let removedNote = removeNoteFromCurrentFolder(noteID: noteID) {
            addNoteToFolder(note: removedNote, folderID: toFolderID)
            
            // Cập nhật selection
            if selectedNoteID == noteID {
                selectedFolderID = toFolderID
            }
            
            // Lưu structure
            saveAllToDisk()
            print("✅ Moved note '\(note.title)' to new folder")
        }
    }
    
    /// Tìm và xóa folder từ vị trí hiện tại, trả về folder đã xóa
    private func removeFolderFromParent(folderID: UUID) -> NoteFolder? {
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
    
    /// Di chuyển folder vào folder khác (thành subfolder)
    private func moveFolder(folderID: UUID, toParentFolderID: UUID?) {
        // Không di chuyển vào chính nó
        if let targetID = toParentFolderID, folderID == targetID {
            print("⚠️ Cannot move folder into itself")
            return
        }
        
        // Không di chuyển vào con/cháu của nó (tránh vòng lặp)
        if let targetID = toParentFolderID, isDescendant(folderID: targetID, ofFolderID: folderID) {
            print("⚠️ Cannot move folder into its descendant")
            return
        }
        
        // Lấy thông tin folder cần di chuyển
        guard let folder = getFolder(folderID: folderID) else {
            print("❌ Cannot find folder to move")
            return
        }
        
        // Lấy đường dẫn folder cha hiện tại (nếu có)
        let sourceParentPath = vaultManager.getParentFolderPath(folderID: folderID, in: folders) ?? []
        
        // Lấy đường dẫn folder cha đích
        let destParentPath: [String]
        if let targetID = toParentFolderID {
            guard let path = vaultManager.getFolderPath(folderID: targetID, in: folders) else {
                print("❌ Cannot find target folder path")
                return
            }
            destParentPath = path
        } else {
            destParentPath = [] // Di chuyển ra root
        }
        
        // Kiểm tra xem folder đã ở vị trí đích chưa
        if sourceParentPath == destParentPath {
            print("ℹ️ Folder is already at target location")
            return
        }
        
        // Di chuyển trên disk trước
        let success = vaultManager.moveFolderOnDisk(
            folderName: folder.name,
            fromParentNames: sourceParentPath,
            toParentNames: destParentPath
        )
        
        guard success else {
            print("❌ Failed to move folder on disk")
            return
        }
        
        // Cập nhật in-memory
        if let removedFolder = removeFolderFromParent(folderID: folderID) {
            if let targetID = toParentFolderID {
                // Thêm vào folder đích
                updateFolder(folderID: targetID) { parent in
                    parent.children.insert(removedFolder, at: 0)
                }
            } else {
                // Thêm vào root
                folders.insert(removedFolder, at: 0)
            }
            
            // Lưu structure
            saveAllToDisk()
            print("✅ Moved folder '\(folder.name)' to new location")
        }
    }
    
    /// Xử lý drop vào folder (có thể là note hoặc folder)
    private func handleDropOnFolder(items: [UUID], targetFolderID: UUID) -> Bool {
        guard let itemID = items.first else { return false }
        
        if isNoteID(itemID) {
            // Đây là note - di chuyển note vào folder
            moveNote(noteID: itemID, toFolderID: targetFolderID)
            return true
        } else if isFolderID(itemID) {
            // Đây là folder - di chuyển folder thành subfolder
            moveFolder(folderID: itemID, toParentFolderID: targetFolderID)
            return true
        }
        
        return false
    }
    
    /// Xử lý drop vào root (chỉ cho folder)
    private func handleDropOnRoot(items: [UUID]) -> Bool {
        guard let itemID = items.first else { return false }
        
        if isFolderID(itemID) {
            // Di chuyển folder ra root
            moveFolder(folderID: itemID, toParentFolderID: nil)
            return true
        }
        
        return false
    }

    // MARK: - Text Highlighting
    
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
    
    // MARK: - Data Loading
    
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
