//
//  ContentView.swift
//  MonkeyNote
//
//  Created by Nguyen Ngoc Khanh on 24/12/25.
//  Refactored on 03/01/26.
//

import SwiftUI

// MARK: - Main View

struct ContentView: View {
    @State private var viewModel = ContentViewModel()
    
    var body: some View {
        NavigationSplitView {
            SidebarView()
        } content: {
            NotesListView()
        } detail: {
            DetailEditorView()
        }
        .environment(viewModel)
        .task {
            viewModel.vaultManager.createVaultIfNeeded()
            viewModel.loadFromVault()
            viewModel.ensureInitialSelection()
            viewModel.refreshTrash()
            viewModel.startWatchingVault()
            viewModel.startWatchingCurrentFile()
        }
        .sheet(item: $viewModel.renameRequest) { request in
            RenameSheet(
                title: request.title,
                placeholder: request.placeholder,
                initialText: request.initialText,
                onCancel: { viewModel.renameRequest = nil },
                onSave: { newName in
                    viewModel.applyRename(request: request, newName: newName)
                    viewModel.renameRequest = nil
                }
            )
        }
        .sheet(isPresented: $viewModel.showSettings) {
            SettingsView(
                vaultManager: viewModel.vaultManager,
                onVaultChanged: {
                    print("💾 Saving current vault before change...")
                    viewModel.isChangingVault = true
                    viewModel.saveAllToDisk()
                }
            )
            .presentationDetents([.medium])
            .presentationDragIndicator(.visible)
        }
        .preferredColorScheme(viewModel.isDarkMode ? .dark : .light)
        .onChange(of: viewModel.vaultManager.vaultURL) { _, newURL in
            print("🔄 Vault changed, resetting folders...")
            viewModel.isChangingVault = false
            viewModel.folders = []
            viewModel.selectedFolderID = nil
            viewModel.selectedNoteID = nil
            viewModel.searchText = ""
            viewModel.trashItems = []
            
            viewModel.loadFromVault()
            viewModel.ensureInitialSelection()
            viewModel.refreshTrash()
            viewModel.startWatchingVault()
            viewModel.startWatchingCurrentFile()
            
            print("📂 Switched to vault: \(newURL?.path ?? "none")")
        }
        .onChange(of: viewModel.selectedNoteID) { _, _ in
            viewModel.startWatchingCurrentFile()
        }
        .onChange(of: viewModel.externalFileURL) { _, _ in
            viewModel.startWatchingCurrentFile()
        }
        .onDisappear {
            viewModel.stopWatching()
            guard !viewModel.isChangingVault else {
                print("⏭️ Skipping save - vault is changing")
                return
            }
            viewModel.saveAllToDisk()
        }
    }
}

// MARK: - Preview

#Preview {
    ContentView()
}
