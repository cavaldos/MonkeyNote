//
//  SidebarView.swift
//  MonkeyNote
//
//  Created by Assistant on 03/01/26.
//

import SwiftUI

struct SidebarView: View {
    @Environment(ContentViewModel.self) var viewModel
    
    // Local state
    @State private var dragOverFolderID: NoteFolder.ID?
    @State private var hoverFolderID: NoteFolder.ID?
    
    var body: some View {
        @Bindable var vm = viewModel
        
        ZStack {
            sidebarBackground
            
            VStack(spacing: 0) {
                List(selection: $vm.selectedFolderID) {
                    // Folders section
                    Section("Folders") {
                        OutlineGroup(viewModel.folders, children: \.outlineChildren) { folder in
                            FolderRowView(
                                folder: folder,
                                hoverFolderID: $hoverFolderID,
                                dragOverFolderID: $dragOverFolderID
                            )
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
                        return viewModel.handleDropOnRoot(items: [itemID])
                    } isTargeted: { isTargeted in
                        // Visual feedback when dragging over root drop zone
                    }
                    
                    // Trash section
                    Section("Trash") {
                        Button {
                            viewModel.showTrash = true
                            viewModel.refreshTrash()
                        } label: {
                            HStack {
                                Label("Trash", systemImage: "trash")
                                Spacer()
                                if !viewModel.trashItems.isEmpty {
                                    Text("\(viewModel.trashItems.count)")
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
                .listStyle(.sidebar)
                .scrollContentBackground(.hidden)
                
                // Bottom toolbar
                HStack(spacing: 12) {
                    Button {
                        viewModel.addFolder(atRoot: true)
                    } label: {
                        Image(systemName: "folder.badge.plus")
                    }
                    
                    Button {
                        viewModel.showSettings = true
                    } label: {
                        Image(systemName: "gear")
                    }
                }
                .padding(16)
            }
        }
        .navigationTitle("Folders")
        .sheet(isPresented: $vm.showTrash) {
            TrashView(
                trashItems: $vm.trashItems,
                onRestore: { item in
                    viewModel.restoreTrashItem(item)
                },
                onDelete: { item in
                    viewModel.deleteTrashItem(item)
                },
                onEmptyTrash: {
                    viewModel.emptyTrash()
                }
            )
            .frame(minWidth: 700, minHeight: 500)
        }
    }
    
    // MARK: - Background
    
    private var sidebarBackground: some View {
        Group {
            #if os(macOS)
            if viewModel.vibrancyEnabled {
                VisualEffectBlur(material: vibrancyMaterial, blendingMode: .behindWindow, state: .active)
            } else {
                VisualEffectBlur(material: .sidebar, blendingMode: .behindWindow)
                    .overlay(
                        (viewModel.isDarkMode ? Color.black.opacity(0.10) : Color.white.opacity(0.10))
                    )
            }
            #else
            Group {
                if viewModel.isDarkMode {
                    Color(red: 49.0 / 255.0, green: 49.0 / 255.0, blue: 49.0 / 255.0)
                } else {
                    Color(red: 0.97, green: 0.97, blue: 0.97)
                }
            }
            #endif
        }
        .ignoresSafeArea()
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
        default: return .sidebar
        }
    }
    #endif
}
