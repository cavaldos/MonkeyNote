//
//  ContentViewModel.swift
//  MonkeyNote
//
//  Created by Assistant on 03/01/26.
//

import SwiftUI
import Combine
import Observation

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
    
    // MARK: - File Watcher
    let fileWatcher = FileWatcherService()
    
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
    
    // MARK: - Cursor State
    var cursorLine: Int = 1
    
    /// Set cursor line only when it actually changed. @Observable fires on
    /// every set, and this is called on every selection change (i.e. every
    /// keystroke) — without the guard each keystroke renders the whole UI
    /// twice (once for text, once for the unchanged line number).
    func updateCursorLine(_ line: Int) {
        if cursorLine != line {
            cursorLine = line
        }
    }

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
        // Unset (nil) means "never configured" — fall back to a delay that
        // keeps typing smooth. NSSpellChecker.completions runs synchronously
        // (~ms) on the main thread per keystroke, so near-zero delays make
        // every keystroke block on the dictionary. An explicit 0 still means
        // "instant" for users who want it.
        get { UserDefaults.standard.object(forKey: "note.autocompleteDelay") as? Double ?? 0.3 }
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
    
    var vibrancyEnabled: Bool {
        get { UserDefaults.standard.object(forKey: "note.vibrancyEnabled") as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: "note.vibrancyEnabled") }
    }
    
    var vibrancyMaterial: String {
        get { UserDefaults.standard.string(forKey: "note.vibrancyMaterial") ?? "hudWindow" }
        set { UserDefaults.standard.set(newValue, forKey: "note.vibrancyMaterial") }
    }

    var showLineNumbers: Bool {
        get { UserDefaults.standard.object(forKey: "note.showLineNumbers") as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: "note.showLineNumbers") }
    }

    var windowAlwaysOnTop: Bool = UserDefaults.standard.object(forKey: "note.windowAlwaysOnTop") as? Bool ?? false {
        didSet {
            UserDefaults.standard.set(windowAlwaysOnTop, forKey: "note.windowAlwaysOnTop")
        }
    }
    
    // MARK: - Silent typing draft (gõ mượt: 0 notify mỗi keystroke)
    @ObservationIgnored private var hasEditorDraft = false
    @ObservationIgnored private var editorDraftIsExternal = false
    @ObservationIgnored private var editorDraftNoteID: NoteItem.ID?
    @ObservationIgnored private var editorDraftText = ""

    // MARK: - Debounced Save State
    // Typing must never block on disk I/O: each keystroke only mutates memory,
    // disk writes are debounced and run on a background queue.
    private var pendingNoteSaveWorkItem: DispatchWorkItem?
    private var pendingNoteSnapshot: (fileURL: URL, oldFileURL: URL?, text: String, title: String, noteID: NoteItem.ID, folderID: NoteFolder.ID)?
    private var pendingStructureSaveWorkItem: DispatchWorkItem?
    private var pendingExternalSaveWorkItem: DispatchWorkItem?
    private let saveQueue = DispatchQueue(label: "MonkeyNote.save", qos: .utility)
    
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
        if isEditingExternalFile { return liveExternalText }
        guard let note = selectedNote else { return "" }
        return liveTextFor(noteID: note.id, nominal: note.text)
    }
    
    // Single-pass document stats, cached by text equality (memcmp-fast).
    // StatusBar reads wordCount/lineCount/characterCount on every render, so
    // without the cache each keystroke scans the document 3 times.
    // @ObservationIgnored: refresh chạy trong lúc render body — nếu để
    // observable thì mỗi phím gõ notify SwiftUI re-render cả cây, updateNSView
    // thấy Binding cũ (chưa commit draft) sẽ reset textView.string → mất chữ,
    // con trỏ nhảy lung tung. Stats chấp nhận trễ 1 nhịp debounce (0.8s).
    @ObservationIgnored private var _statsText = ""
    @ObservationIgnored private var _statsWords = 0
    @ObservationIgnored private var _statsLines = 1
    @ObservationIgnored private var _statsChars = 0
    // File lớn: đếm lại mỗi keystroke là full scan O(N) → throttle 1/s,
    // hẹn refresh 1 lần sau khi ngừng gõ để số liệu đúng lại.
    @ObservationIgnored private var _statsLastLargeRefresh = Date.distantPast
    @ObservationIgnored private var _statsRefreshPending = false
    
    private func refreshStatsIfNeeded() {
        let t = activeText
        if t == _statsText { return }
        // Giữ đồng bộ với CursorTextView.largeDocumentLengthThreshold (file này
        // build cả iOS nên không tham chiếu trực tiếp class macOS-only đó).
        if t.utf16.count > 300_000 {
            if Date().timeIntervalSince(_statsLastLargeRefresh) < 1.0 {
                if !_statsRefreshPending {
                    _statsRefreshPending = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
                        self?._statsRefreshPending = false
                        self?.refreshStatsIfNeeded()
                    }
                }
                return
            }
            _statsLastLargeRefresh = Date()
        }
        // UTF-16 single pass (~0.1ms for a 3000-word doc vs ~1.5ms iterating
        // Characters). Approximation notes: non-ASCII whitespace (e.g. NBSP)
        // counts as a word char, combining marks/ZWJ sequences count as one
        // char per UTF-16 unit pair — fine for a status bar.
        var w = 0, l = 1, ch = 0, inWord = false, prevCR = false
        for u in t.utf16 {
            if u == 0xA { // LF: line break, not a char (\r\n counts once)
                if !prevCR { l += 1 }
                inWord = false
                prevCR = false
                continue
            }
            if u >= 0xD800 && u < 0xDC00 { // high surrogate: char counted at low surrogate
                prevCR = false
                if !inWord { inWord = true; w += 1 }
                continue
            }
            ch += 1
            if u == 0xD { // CR
                l += 1
                inWord = false
                prevCR = true
            } else if u == 0x20 || u == 0x9 || u == 0xB || u == 0xC {
                inWord = false
                prevCR = false
            } else {
                prevCR = false
                if !inWord { inWord = true; w += 1 }
            }
        }
        _statsText = t
        _statsWords = w
        _statsLines = l
        _statsChars = ch
    }
    
    var wordCount: Int {
        refreshStatsIfNeeded()
        return _statsWords
    }
    
    var lineCount: Int {
        refreshStatsIfNeeded()
        return _statsLines
    }
    
    var characterCount: Int {
        refreshStatsIfNeeded()
        return _statsChars
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
                get: { [weak self] in self?.liveExternalText ?? "" },
                set: { [weak self] newValue in
                    self?.hasEditorDraft = false
                    self?.externalFileText = newValue
                    self?.scheduleDebouncedExternalSave()
                }
            )
        } else {
            return selectedNoteTextBinding
        }
    }
    
    var selectedNoteTextBinding: Binding<String> {
        Binding(
            get: { [weak self] in
                // Draft-aware: lúc đang gõ, text thật nằm ở editorDraftText
                // (@ObservationIgnored, chưa commit). Trả nominal (note.text)
                // ở đây thì updateNSView thấy textView.string != text sau bất kỳ
                // re-render nào (đổi dòng status, search count...) sẽ reset
                // textView về bản cũ → mất chữ + con trỏ nhảy.
                guard let self, let note = self.selectedNote else { return "" }
                return self.liveTextFor(noteID: note.id, nominal: note.text)
            },
            set: { [weak self] newValue in
                guard let self = self,
                      let selectedFolderID = self.selectedFolderID,
                      let selectedNoteID = self.selectedNoteID else { return }
                // Write-through ngoài (hiếm): bỏ draft cũ cho khỏi đè.
                if self.hasEditorDraft && !self.editorDraftIsExternal
                    && self.editorDraftNoteID == selectedNoteID {
                    self.hasEditorDraft = false
                }
                self.updateFolder(folderID: selectedFolderID) { folder in
                    guard let noteIndex = folder.notes.firstIndex(where: { $0.id == selectedNoteID }) else { return }
                    folder.notes[noteIndex].text = newValue
                    folder.notes[noteIndex].updatedAt = Date()
                    // Retitle không làm ở đây nữa — dồn vào lúc flush debounce
                    // (syncNoteTitleIfNeeded), mỗi keystroke không đụng title.
                }
                self.scheduleDebouncedNoteSave()
            }
        )
    }

    /// Đường gõ phím chính: textView là source of truth mỗi keystroke, text
    /// chỉ nằm ở draft @ObservationIgnored (không notify → SwiftUI không
    /// re-render cả cây sidebar/list/editor/status mỗi phím). Draft commit
    /// 1 lần lúc debounce-fire / chuyển note / save. Ngoại lệ duy nhất:
    /// doc chuyển rỗng↔có-chữ thì write-through để placeholder ẩn/hiện đúng.
    func applyEditorText(_ newText: String) {
        if isEditingExternalFile {
            guard externalFileURL != nil else { return }
            let old = (hasEditorDraft && editorDraftIsExternal) ? editorDraftText : externalFileText
            if Self.isEffectivelyEmpty(old) != Self.isEffectivelyEmpty(newText) {
                hasEditorDraft = false
                externalFileText = newText
            } else {
                editorDraftIsExternal = true
                editorDraftNoteID = nil
                editorDraftText = newText
                hasEditorDraft = true
            }
            scheduleDebouncedExternalSave()
            return
        }
        guard let selectedNoteID,
              let folder = findFolderContainingNote(noteID: selectedNoteID),
              let note = folder.notes.first(where: { $0.id == selectedNoteID }) else { return }
        let old = liveTextFor(noteID: selectedNoteID, nominal: note.text)
        if Self.isEffectivelyEmpty(old) != Self.isEffectivelyEmpty(newText) {
            hasEditorDraft = false
            updateFolder(folderID: folder.id) { f in
                guard let i = f.notes.firstIndex(where: { $0.id == selectedNoteID }) else { return }
                f.notes[i].text = newText
                f.notes[i].updatedAt = Date()
            }
        } else {
            editorDraftIsExternal = false
            editorDraftNoteID = selectedNoteID
            editorDraftText = newText
            hasEditorDraft = true
        }
        scheduleDebouncedNoteSave()
    }

    /// Đổ draft vào memory thật (1 notify duy nhất). Gọi ở save-fire, flush,
    /// saveAll, replace — không gọi mỗi keystroke.
    @discardableResult
    private func commitEditorDraft() -> Bool {
        guard hasEditorDraft else { return false }
        hasEditorDraft = false
        if editorDraftIsExternal {
            externalFileText = editorDraftText
            return true
        }
        guard let id = editorDraftNoteID,
              let folder = findFolderContainingNote(noteID: id) else { return false }
        updateFolder(folderID: folder.id) { f in
            guard let i = f.notes.firstIndex(where: { $0.id == id }) else { return }
            f.notes[i].text = editorDraftText
            f.notes[i].updatedAt = Date()
        }
        return true
    }

    /// Text đang sửa (draft-aware). Editor/stats/save đọc qua đây thay vì
    /// đọc thẳng note.text.
    private func liveTextFor(noteID: NoteItem.ID, nominal: String) -> String {
        (hasEditorDraft && !editorDraftIsExternal && editorDraftNoteID == noteID)
            ? editorDraftText : nominal
    }

    private var liveExternalText: String {
        (hasEditorDraft && editorDraftIsExternal) ? editorDraftText : externalFileText
    }

    private static func isEffectivelyEmpty(_ s: String) -> Bool {
        s.first(where: { !$0.isWhitespace && !$0.isNewline }) == nil
    }

    /// Retitle debounce: chỉ chạy lúc flush save (≤1 lần/nhịp gõ), không phải mỗi phím.
    private func syncNoteTitleIfNeeded(noteID: NoteItem.ID) {
        guard let folder = findFolderContainingNote(noteID: noteID),
              let note = folder.notes.first(where: { $0.id == noteID }),
              !note.isTitleCustom,
              note.text.first(where: { !$0.isWhitespace && !$0.isNewline }) != nil else { return }
        let base = firstLineTitle(from: note.text)
        guard base != note.title else { return }
        let unique = uniqueNoteTitle(base, in: folder.notes, excludingNoteID: noteID)
        guard unique != note.title else { return }
        updateFolder(folderID: folder.id) { f in
            if let i = f.notes.firstIndex(where: { $0.id == noteID }) {
                f.notes[i].title = unique
            }
        }
    }
    
    // MARK: - Initialization
    
    init() {
        // Set default for isDarkMode if not set
        if UserDefaults.standard.object(forKey: "note.isDarkMode") == nil {
            UserDefaults.standard.set(true, forKey: "note.isDarkMode")
        }
        
        setupFileWatcher()
    }
    
    // MARK: - Data Loading
    
    func loadFromVault() {
        folders = vaultManager.loadFolders()
        print("📂 Loaded \(folders.count) folders from vault")
    }
    
    func saveAllToDisk() {
        // Commit draft gõ dở trước: save toàn bộ mà quên draft là mất chữ.
        commitEditorDraft()
        // A full sync save supersedes any pending debounced writes (memory
        // already holds the latest text, so nothing is lost).
        pendingNoteSaveWorkItem?.cancel()
        pendingNoteSaveWorkItem = nil
        pendingNoteSnapshot = nil
        pendingStructureSaveWorkItem?.cancel()
        pendingStructureSaveWorkItem = nil
        pendingExternalSaveWorkItem?.cancel()
        pendingExternalSaveWorkItem = nil
        fileWatcher.notifyWillSave()
        folders = vaultManager.saveFolders(folders)
        fileWatcher.notifyDidSave()
        fileWatcher.updateVaultSnapshot()
    }
    
    // MARK: - Debounced Saves (typing path)
    
    /// Debounced single-note save: memory is already updated by the caller,
    /// only one .md file is written, on a background queue. The snapshot is
    /// captured now (while the note is still selected), so a later note
    /// switch can't redirect the write to the wrong file.
    func scheduleDebouncedNoteSave(delay: TimeInterval = 0.8) {
        pendingNoteSaveWorkItem?.cancel()
        guard let snapshot = currentNoteSaveSnapshot() else { return }
        pendingNoteSnapshot = snapshot
        let workItem = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.pendingNoteSaveWorkItem = nil
            // Đổ draft 1 lần (1 notify), rồi retitle + snapshot text mới nhất.
            self.commitEditorDraft()
            // Retitle debounce ở đây (≤1 lần/nhịp gõ), xong mới snapshot để
            // tên file trên đĩa đúng luôn.
            self.syncNoteTitleIfNeeded(noteID: snapshot.noteID)
            // Re-snapshot: a later keystroke rescheduled us, so take the latest text.
            let latest = self.currentNoteSaveSnapshotFor(noteID: snapshot.noteID) ?? snapshot
            self.pendingNoteSnapshot = nil
            self.writeNoteSnapshot(latest, syncSavedTitle: true)
        }
        pendingNoteSaveWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: workItem)
    }
    
    /// Write pending note to disk now (single file, sync — cheap enough for
    /// note switches / app backgrounding, and safe even after selection changed).
    func flushPendingNoteSave() {
        pendingNoteSaveWorkItem?.cancel()
        pendingNoteSaveWorkItem = nil
        commitEditorDraft()
        guard let snapshot = pendingNoteSnapshot ?? currentNoteSaveSnapshot() else { return }
        pendingNoteSnapshot = nil
        syncNoteTitleIfNeeded(noteID: snapshot.noteID)
        let latest = currentNoteSaveSnapshotFor(noteID: snapshot.noteID) ?? snapshot
        writeNoteSnapshot(latest, syncSavedTitle: true)
    }
    
    /// Snapshot of what needs writing for the currently selected note.
    private func currentNoteSaveSnapshot() -> (fileURL: URL, oldFileURL: URL?, text: String, title: String, noteID: NoteItem.ID, folderID: NoteFolder.ID)? {
        guard let note = selectedNote,
              let folderID = selectedFolderID,
              let folderPath = vaultManager.getFolderPath(folderID: folderID, in: folders),
              let fileURL = vaultManager.noteFileURL(noteTitle: note.title, folderPath: folderPath) else { return nil }
        let oldFileURL: URL? = (note.savedTitle != note.title)
            ? vaultManager.noteFileURL(noteTitle: note.savedTitle, folderPath: folderPath)
            : nil
        return (fileURL, oldFileURL, liveTextFor(noteID: note.id, nominal: note.text), note.title, note.id, folderID)
    }
    
    /// Snapshot for a specific note ID (used at debounce-fire time so the
    /// latest text wins even if selection already moved elsewhere).
    private func currentNoteSaveSnapshotFor(noteID: NoteItem.ID) -> (fileURL: URL, oldFileURL: URL?, text: String, title: String, noteID: NoteItem.ID, folderID: NoteFolder.ID)? {
        guard let folder = findFolderContainingNote(noteID: noteID),
              let note = folder.notes.first(where: { $0.id == noteID }),
              let folderPath = vaultManager.getFolderPath(folderID: folder.id, in: folders),
              let fileURL = vaultManager.noteFileURL(noteTitle: note.title, folderPath: folderPath) else { return nil }
        let oldFileURL: URL? = (note.savedTitle != note.title)
            ? vaultManager.noteFileURL(noteTitle: note.savedTitle, folderPath: folderPath)
            : nil
        return (fileURL, oldFileURL, liveTextFor(noteID: note.id, nominal: note.text), note.title, note.id, folder.id)
    }
    
    private func writeNoteSnapshot(_ snapshot: (fileURL: URL, oldFileURL: URL?, text: String, title: String, noteID: NoteItem.ID, folderID: NoteFolder.ID), syncSavedTitle: Bool) {
        fileWatcher.notifyWillSave()
        let oldFileURL = snapshot.oldFileURL
        let fileURL = snapshot.fileURL
        saveQueue.async { [weak self] in
            do {
                try snapshot.text.write(to: fileURL, atomically: true, encoding: .utf8)
                if let oldFileURL, oldFileURL != fileURL {
                    try? FileManager.default.removeItem(at: oldFileURL)
                }
            } catch {
                print("❌ Failed to save \(fileURL.lastPathComponent): \(error)")
            }
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                if syncSavedTitle {
                    // Sync savedTitle without scheduling another save (no loop:
                    // this mutation never calls scheduleDebouncedNoteSave).
                    self.updateFolder(folderID: snapshot.folderID) { folder in
                        if let i = folder.notes.firstIndex(where: { $0.id == snapshot.noteID }),
                           folder.notes[i].title == snapshot.title {
                            folder.notes[i].savedTitle = snapshot.title
                        }
                    }
                }
                self.fileWatcher.notifyDidSave()
                self.fileWatcher.updateVaultSnapshot()
                // Titles live in the structure JSON — persist it debounced.
                self.scheduleDebouncedStructureSave()
            }
        }
    }
    
    /// Debounced structure-JSON save (titles only — NoteItem encoding
    /// excludes text, so this stays small; encode on main, only the file
    /// write goes to background).
    private func scheduleDebouncedStructureSave(delay: TimeInterval = 2.5) {
        pendingStructureSaveWorkItem?.cancel()
        let snapshot = folders
        let vaultManager = vaultManager
        let workItem = DispatchWorkItem { [weak self] in
            guard let self else { return }
            let structureURL = vaultManager.vaultURL?.appendingPathComponent(".vault-structure.json")
            let data: Data?
            do {
                let encoder = JSONEncoder()
                encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
                encoder.dateEncodingStrategy = .iso8601
                data = try encoder.encode(VaultData(folders: snapshot))
            } catch {
                print("❌ Failed to save structure: \(error)")
                data = nil
            }
            guard let data, let structureURL else {
                self.pendingStructureSaveWorkItem = nil
                return
            }
            self.saveQueue.async { [weak self] in
                try? data.write(to: structureURL)
                DispatchQueue.main.async { [weak self] in
                    self?.pendingStructureSaveWorkItem = nil
                    self?.fileWatcher.updateVaultSnapshot()
                }
            }
        }
        pendingStructureSaveWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: workItem)
    }
    
    /// Debounced external-file save (same lag source as vault notes).
    private func scheduleDebouncedExternalSave(delay: TimeInterval = 0.8) {
        pendingExternalSaveWorkItem?.cancel()
        let workItem = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.pendingExternalSaveWorkItem = nil
            self.saveExternalFile()
        }
        pendingExternalSaveWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: workItem)
    }
    
    func refreshTrash() {
        trashItems = vaultManager.scanTrash(currentFolders: folders)
    }
    
    // MARK: - File Watcher
    
    private func setupFileWatcher() {
        fileWatcher.onFileContentChanged = { [weak self] newContent in
            guard let self else { return }
            
            if self.isEditingExternalFile {
                // External file changed on disk (so với text đang thấy,
                // gồm cả draft gõ dở — đĩa thắng, bỏ draft).
                guard newContent != self.liveExternalText else { return }
                self.hasEditorDraft = false
                self.externalFileText = newContent
                print("🔄 External file reloaded from disk")
            } else {
                // Vault note changed on disk
                guard let note = self.selectedNote,
                      newContent != self.liveTextFor(noteID: note.id, nominal: note.text) else { return }
                self.updateSelectedNoteText(newContent)
                print("🔄 Note reloaded from disk")
            }
        }
        
        fileWatcher.onVaultStructureChanged = { [weak self] in
            guard let self else { return }
            let currentNoteID = self.selectedNoteID
            let currentFolderID = self.selectedFolderID
            
            self.folders = self.vaultManager.loadFolders()
            
            // Restore selection
            self.selectedFolderID = currentFolderID
            self.selectedNoteID = currentNoteID
            self.refreshTrash()
            print("🔄 Vault structure reloaded from disk")
        }
    }
    
    /// Start watching the currently selected note or external file.
    func startWatchingCurrentFile() {
        if let url = externalFileURL {
            fileWatcher.watchFile(at: url)
        } else if let fileURL = currentNoteFileURL {
            fileWatcher.watchFile(at: fileURL)
        } else {
            fileWatcher.stopWatchingFile()
        }
    }
    
    /// Start watching the vault directory for structural changes.
    func startWatchingVault() {
        guard let vaultURL = vaultManager.vaultURL else { return }
        fileWatcher.watchVault(at: vaultURL)
    }
    
    /// Stop all file watching.
    func stopWatching() {
        fileWatcher.stopAll()
    }
    
    /// Update the selected note's text without triggering a save (used for external changes).
    private func updateSelectedNoteText(_ newContent: String) {
        guard let selectedFolderID, let selectedNoteID else { return }
        // Đĩa thắng: bỏ draft gõ dở của note này.
        if hasEditorDraft && !editorDraftIsExternal && editorDraftNoteID == selectedNoteID {
            hasEditorDraft = false
        }
        updateFolder(folderID: selectedFolderID) { folder in
            guard let noteIndex = folder.notes.firstIndex(where: { $0.id == selectedNoteID }) else { return }
            folder.notes[noteIndex].text = newContent
        }
    }
    
    /// Get the file URL for the currently selected note.
    private var currentNoteFileURL: URL? {
        guard let note = selectedNote,
              let folderID = selectedFolderID,
              let path = vaultManager.getFolderPath(folderID: folderID, in: folders) else { return nil }
        return vaultManager.noteFileURL(noteTitle: note.title, folderPath: path)
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
        commitEditorDraft()
        guard let url = externalFileURL else { return }
        fileWatcher.notifyWillSave()
        do {
            try externalFileText.write(to: url, atomically: true, encoding: .utf8)
            print("💾 Saved external file: \(url.path)")
        } catch {
            print("❌ Failed to save external file: \(error)")
        }
        fileWatcher.notifyDidSave()
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
        // Guard từng cái như updateCursorLine: callback này bắn sau mỗi layout
        // (debouncedUpdateHighlights) kể cả khi không search — gán mù sẽ
        // notify SwiftUI render cả cây + memcmp full text mỗi lần nhấn mũi tên.
        if searchMatchCount != count { searchMatchCount = count }
        if isSearchComplete != isComplete { isSearchComplete = isComplete }
        let clamped = count > 0 ? min(currentSearchIndex, count - 1) : 0
        if currentSearchIndex != clamped { currentSearchIndex = clamped }
    }
    
    func replaceCurrentMatch() {
        commitEditorDraft()
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
        commitEditorDraft()
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
        // prefix(while:) stops at the first newline — split(whereSeparator:)
        // would scan the whole document on every keystroke.
        let firstLine = String(text.prefix(while: { !$0.isNewline }))
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
        // Rows render with .lineLimit(1) and this runs for every row on every
        // keystroke — only look at the head instead of copying the whole
        // document through replacingOccurrences.
        let head = String(text.prefix(160))
        let singleLine = head
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
