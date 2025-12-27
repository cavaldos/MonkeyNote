//
//  TrashView.swift
//  Note
//
//  Created by Nguyen Ngoc Khanh on 25/12/25.
//

import SwiftUI

struct TrashView: View {
    @Binding var trashItems: [TrashItem]
    let onRestore: (TrashItem) -> Void
    let onDelete: (TrashItem) -> Void
    let onEmptyTrash: () -> Void
    
    @Environment(\.dismiss) private var dismiss
    @State private var showEmptyConfirmation = false
    @State private var selectedItem: TrashItem?
    
    var body: some View {
        Group {
            if trashItems.isEmpty {
                emptyTrashView
            } else {
                trashContentView
            }
        }
        .alert("Empty Trash?", isPresented: $showEmptyConfirmation) {
            Button("Cancel", role: .cancel) { }
            Button("Empty Trash", role: .destructive) {
                selectedItem = nil
                onEmptyTrash()
            }
        } message: {
            Text("This will permanently delete \(trashItems.count) item(s). This action cannot be undone.")
        }
        .onChange(of: trashItems) { _, newItems in
            if let selected = selectedItem, !newItems.contains(where: { $0.id == selected.id }) {
                selectedItem = nil
            }
        }
    }
    
    // MARK: - Empty Trash View (Full Screen)
    
    private var emptyTrashView: some View {
        VStack(spacing: 20) {
            Spacer()
            
            Image(systemName: "trash")
                .font(.system(size: 64))
                .foregroundStyle(.secondary)
            
            Text("Trash is Empty")
                .font(.system(.title, design: .monospaced, weight: .bold))
            
            Text("Deleted items will appear here")
                .font(.system(.body, design: .monospaced))
                .foregroundStyle(.secondary)
            
            Spacer()
            
            // Bottom toolbar
            HStack {
                Button("Done") {
                    dismiss()
                }
                .buttonStyle(.bordered)
            }
            .padding()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    // MARK: - Trash Content View (Split View)
    
    private var trashContentView: some View {
        NavigationSplitView {
            trashListView
                .navigationTitle("Trash")
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Done") {
                            dismiss()
                        }
                    }
                    
                    ToolbarItem(placement: .destructiveAction) {
                        Button("Empty Trash") {
                            showEmptyConfirmation = true
                        }
                    }
                }
        } detail: {
            detailView
        }
    }
    
    // MARK: - List View
    
    private var trashListView: some View {
        List(trashItems, selection: $selectedItem) { item in
            TrashItemRow(item: item)
                .tag(item)
                .contextMenu {
                    Button {
                        onRestore(item)
                        if selectedItem?.id == item.id {
                            selectedItem = nil
                        }
                    } label: {
                        Label("Restore", systemImage: "arrow.uturn.backward")
                    }
                    
                    Button(role: .destructive) {
                        if selectedItem?.id == item.id {
                            selectedItem = nil
                        }
                        onDelete(item)
                    } label: {
                        Label("Delete Permanently", systemImage: "trash")
                    }
                }
        }
    }
    
    // MARK: - Detail View
    
    @ViewBuilder
    private var detailView: some View {
        if let item = selectedItem, trashItems.contains(where: { $0.id == item.id }) {
            TrashItemDetailView(
                item: item,
                onRestore: {
                    selectedItem = nil
                    onRestore(item)
                },
                onDelete: {
                    selectedItem = nil
                    onDelete(item)
                }
            )
        } else {
            ContentUnavailableView(
                "Select an item",
                systemImage: "doc.text",
                description: Text("Choose a file to preview its content")
            )
        }
    }
}

// MARK: - Trash Item Row

struct TrashItemRow: View {
    let item: TrashItem
    
    var body: some View {
        HStack {
            Image(systemName: item.type == .folder ? "folder" : "doc.text")
                .foregroundStyle(item.type == .folder ? .blue : .secondary)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(item.name)
                    .font(.system(.body, design: .monospaced))
                    .lineLimit(1)
                Text(item.relativePath)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Trash Item Detail View

struct TrashItemDetailView: View {
    let item: TrashItem
    let onRestore: () -> Void
    let onDelete: () -> Void
    
    @State private var fileContent: String = ""
    @State private var folderContents: [String] = []
    @State private var isLoading = true
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Image(systemName: item.type == .folder ? "folder.fill" : "doc.text.fill")
                    .font(.title2)
                    .foregroundStyle(item.type == .folder ? .blue : .orange)
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.name)
                        .font(.system(.headline, design: .monospaced))
                    Text(item.relativePath)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
                
                Spacer()
                
                // Action buttons
                HStack(spacing: 12) {
                    Button {
                        onRestore()
                    } label: {
                        Label("Restore", systemImage: "arrow.uturn.backward")
                    }
                    .buttonStyle(.bordered)
                    
                    Button(role: .destructive) {
                        onDelete()
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }
                    .buttonStyle(.bordered)
                }
            }
            .padding()
            .background(Color(nsColor: .windowBackgroundColor))
            
            Divider()
            
            // Content
            if isLoading {
                Spacer()
                ProgressView()
                Spacer()
            } else if item.type == .file {
                // File content preview
                ScrollView {
                    Text(fileContent.isEmpty ? "(Empty file)" : fileContent)
                        .font(.system(.body, design: .monospaced))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding()
                        .textSelection(.enabled)
                }
            } else {
                // Folder contents list
                if folderContents.isEmpty {
                    ContentUnavailableView(
                        "Empty Folder",
                        systemImage: "folder",
                        description: Text("This folder contains no files")
                    )
                } else {
                    List {
                        Section("Contents (\(folderContents.count) items)") {
                            ForEach(folderContents, id: \.self) { name in
                                HStack {
                                    Image(systemName: name.hasSuffix(".md") ? "doc.text" : "folder")
                                        .foregroundStyle(.secondary)
                                    Text(name)
                                        .font(.system(.body, design: .monospaced))
                                }
                            }
                        }
                    }
                }
            }
        }
        .task {
            await loadContent()
        }
        .onChange(of: item) { _, _ in
            Task {
                await loadContent()
            }
        }
    }
    
    private func loadContent() async {
        isLoading = true
        
        if item.type == .file {
            // Read file content
            fileContent = (try? String(contentsOf: item.fullURL, encoding: .utf8)) ?? "(Unable to read file)"
        } else {
            // List folder contents
            let fileManager = FileManager.default
            do {
                let contents = try fileManager.contentsOfDirectory(
                    at: item.fullURL,
                    includingPropertiesForKeys: nil,
                    options: [.skipsHiddenFiles]
                )
                folderContents = contents.map { $0.lastPathComponent }.sorted()
            } catch {
                folderContents = []
            }
        }
        
        isLoading = false
    }
}

#Preview("Empty Trash") {
    TrashView(
        trashItems: .constant([]),
        onRestore: { _ in },
        onDelete: { _ in },
        onEmptyTrash: { }
    )
}

#Preview("With Items") {
    TrashView(
        trashItems: .constant([
            TrashItem(name: "Old Note.md", type: .file, relativePath: "Notes/Old Note.md", fullURL: URL(fileURLWithPath: "/tmp/test.md")),
            TrashItem(name: "Archive", type: .folder, relativePath: "Archive", fullURL: URL(fileURLWithPath: "/tmp/archive"))
        ]),
        onRestore: { _ in },
        onDelete: { _ in },
        onEmptyTrash: { }
    )
}
