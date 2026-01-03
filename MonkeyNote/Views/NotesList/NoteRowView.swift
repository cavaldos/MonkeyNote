//
//  NoteRowView.swift
//  MonkeyNote
//
//  Created by Assistant on 03/01/26.
//

import SwiftUI

struct NoteRowView: View {
    @Environment(ContentViewModel.self) var viewModel
    
    let note: NoteItem
    var folderName: String? = nil  // Optional: shown in global search results
    
    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 4) {
                    // Pin icon
                    if note.isPinned {
                        Image(systemName: "pin.fill")
                            .font(.system(size: 10))
                            .foregroundStyle(.orange)
                    }
                    
                    viewModel.highlightedText(note.title, searchText: viewModel.searchText)
                        .font(.system(.body, design: .monospaced))
                        .lineLimit(1)
                }
                
                // Show folder name in global search, otherwise show preview
                if let folder = folderName {
                    HStack(spacing: 4) {
                        Image(systemName: "folder")
                            .font(.system(size: 10))
                        Text(folder)
                            .font(.system(.footnote, design: .monospaced))
                    }
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                } else {
                    viewModel.highlightedText(viewModel.notePreview(for: note.text), searchText: viewModel.searchText)
                        .font(.system(.footnote, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            
            Spacer()
            
            // Warning indicator for large files
            if note.isTooLarge {
                HStack(spacing: 4) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                        .font(.system(size: 12))
                    Text("\(note.lineCount) lines")
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(.orange)
                }
                .help("File too large to open (max \(VaultManager.maxAllowedLines) lines)")
            }
        }
        .padding(.vertical, 4)
        .tag(note.id)
        .draggable(note.id.uuidString)
        .contextMenu {
            Button {
                viewModel.togglePinNote(noteID: note.id)
            } label: {
                Label(note.isPinned ? "Unpin Note" : "Pin Note",
                      systemImage: note.isPinned ? "pin.slash" : "pin")
            }
            
            Divider()
            
            Button {
                viewModel.startRenameNote(noteID: note.id)
            } label: {
                Text("Rename Note")
            }
            
            Button(role: .destructive) {
                viewModel.deleteNote(noteID: note.id)
            } label: {
                Text("Delete Note")
            }
        }
    }
}
