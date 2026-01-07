//
//  NotesListView.swift
//  MonkeyNote
//
//  Created by Assistant on 03/01/26.
//

import SwiftUI

struct NotesListView: View {
    @Environment(ContentViewModel.self) var viewModel
    
    // Local state
    @State private var showLargeFileAlert: Bool = false
    @State private var largeFileInfo: (name: String, lines: Int)?
    @State private var isVibrancyEnabled: Bool = UserDefaults.standard.object(forKey: "note.vibrancyEnabled") as? Bool ?? true
    
    var body: some View {
        @Bindable var vm = viewModel
        
        ZStack {
            background
            
            if let folder = viewModel.selectedFolder {
                List(selection: Binding(
                    get: { viewModel.selectedNoteID },
                    set: { newValue in
                        // Check if trying to select a large file
                        if let noteID = newValue,
                           let note = folder.notes.first(where: { $0.id == noteID }),
                           note.isTooLarge {
                            // Block selection - show alert
                            largeFileInfo = (note.title, note.lineCount)
                            showLargeFileAlert = true
                            return
                        }
                        
                        // Close external file if selecting vault note
                        if newValue != nil && viewModel.isEditingExternalFile {
                            viewModel.closeExternalFile()
                        }
                        
                        vm.selectedNoteID = newValue
                    }
                )) {
                    ForEach(viewModel.filteredNotes(in: folder)) { note in
                        NoteRowView(note: note)
                    }
                }
                .scrollContentBackground(.hidden)
                .clipped()
                .id(viewModel.searchText)
            } else {
                Text("Choose a folder")
                    .foregroundStyle(.secondary)
            }
        }
        .clipped()
        .navigationTitle(viewModel.selectedFolderID == nil ? "Notes" : (viewModel.selectedFolder?.name ?? "Notes"))
        #if os(macOS)
        .toolbarBackground(isVibrancyEnabled ? .visible : .hidden, for: .windowToolbar)
        .toolbarBackground(Material.ultraThinMaterial, for: .windowToolbar)
        #endif
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                HStack(spacing: 8) {
                    // Sort menu
                    sortMenu
                    
                    // Add note button
                    Button {
                        viewModel.addNote()
                    } label: {
                        Image(systemName: "square.and.pencil")
                    }
                    .disabled(viewModel.selectedFolderID == nil)
                }
            }
        }
        .alert("File Too Large", isPresented: $showLargeFileAlert) {
            Button("OK", role: .cancel) { }
        } message: {
            if let info = largeFileInfo {
                Text("\"\(info.name)\" has \(info.lines) lines.\nMaximum allowed: \(VaultManager.maxAllowedLines) lines.")
            }
        }
        #if os(macOS)
        .onReceive(NotificationCenter.default.publisher(for: .vibrancySettingChanged)) { _ in
            isVibrancyEnabled = UserDefaults.standard.object(forKey: "note.vibrancyEnabled") as? Bool ?? true
        }
        #endif
    }
    
    // MARK: - Background
    
    private var background: some View {
        Group {
            #if os(macOS)
            if viewModel.vibrancyEnabled {
                Color.clear
                    .background(
                        VisualEffectBlur(
                            material: vibrancyMaterial,
                            blendingMode: .behindWindow,
                            state: .active
                        )
                    )
            } else {
                solidBackground
            }
            #else
            solidBackground
            #endif
        }
        .ignoresSafeArea()
    }
    
    private var solidBackground: some View {
        Group {
            if viewModel.isDarkMode {
                Color(red: 49.0 / 255.0, green: 49.0 / 255.0, blue: 49.0 / 255.0)
            } else {
                Color(red: 0.97, green: 0.97, blue: 0.97)
            }
        }
    }
    
    #if os(macOS)
    private var vibrancyMaterial: NSVisualEffectView.Material {
        switch viewModel.vibrancyMaterial {
        case "hudWindow": return .hudWindow
        case "popover": return .popover
        case "sidebar": return .sidebar
        case "underWindowBackground": return .underWindowBackground
        case "headerView": return .headerView
        case "sheet": return .sheet
        case "windowBackground": return .windowBackground
        case "menu": return .menu
        case "contentBackground": return .contentBackground
        case "titlebar": return .titlebar
        default: return .hudWindow
        }
    }
    #endif
    
    // MARK: - Sort Menu
    
    private var sortMenu: some View {
        @Bindable var vm = viewModel
        
        return Menu {
            Button {
                vm.sortOptionRaw = NoteSortOption.nameAscending.rawValue
            } label: {
                if viewModel.sortOption == .nameAscending {
                    Label("Name A-Z", systemImage: "checkmark")
                } else {
                    Text("Name A-Z")
                }
            }
            
            Button {
                vm.sortOptionRaw = NoteSortOption.nameDescending.rawValue
            } label: {
                if viewModel.sortOption == .nameDescending {
                    Label("Name Z-A", systemImage: "checkmark")
                } else {
                    Text("Name Z-A")
                }
            }
            
            Button {
                vm.sortOptionRaw = NoteSortOption.dateNewest.rawValue
            } label: {
                if viewModel.sortOption == .dateNewest {
                    Label("Date Newest", systemImage: "checkmark")
                } else {
                    Text("Date Newest")
                }
            }
            
            Button {
                vm.sortOptionRaw = NoteSortOption.dateOldest.rawValue
            } label: {
                if viewModel.sortOption == .dateOldest {
                    Label("Date Oldest", systemImage: "checkmark")
                } else {
                    Text("Date Oldest")
                }
            }
            
            Button {
                vm.sortOptionRaw = NoteSortOption.createdNewest.rawValue
            } label: {
                if viewModel.sortOption == .createdNewest {
                    Label("Created Newest", systemImage: "checkmark")
                } else {
                    Text("Created Newest")
                }
            }
            
            Button {
                vm.sortOptionRaw = NoteSortOption.createdOldest.rawValue
            } label: {
                if viewModel.sortOption == .createdOldest {
                    Label("Created Oldest", systemImage: "checkmark")
                } else {
                    Text("Created Oldest")
                }
            }
        } label: {
            Image(systemName: "arrow.up.arrow.down")
        }
        .menuIndicator(.hidden)
        .help("Sort notes")
    }
}
