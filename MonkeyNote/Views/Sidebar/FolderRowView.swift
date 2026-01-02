//
//  FolderRowView.swift
//  MonkeyNote
//
//  Created by Assistant on 03/01/26.
//

import SwiftUI

struct FolderRowView: View {
    @Environment(ContentViewModel.self) var viewModel
    
    let folder: NoteFolder
    @Binding var hoverFolderID: NoteFolder.ID?
    @Binding var dragOverFolderID: NoteFolder.ID?
    
    var body: some View {
        HStack {
            Label(folder.name, systemImage: "folder")
            Spacer()
            
            // Menu button - only visible on hover
            if hoverFolderID == folder.id {
                Menu {
                    Button {
                        viewModel.addSubfolder(parentFolderID: folder.id)
                    } label: {
                        Label("New Folder", systemImage: "folder.badge.plus")
                    }
                    
                    Button {
                        viewModel.startRenameFolder(folderID: folder.id)
                    } label: {
                        Label("Rename Folder", systemImage: "pencil")
                    }
                    
                    Divider()
                    
                    Button(role: .destructive) {
                        viewModel.deleteFolder(folderID: folder.id)
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
            return viewModel.handleDropOnFolder(items: [itemID], targetFolderID: folder.id)
        } isTargeted: { isTargeted in
            withAnimation(.easeInOut(duration: 0.15)) {
                dragOverFolderID = isTargeted ? folder.id : nil
            }
        }
        .listRowInsets(EdgeInsets(top: 2, leading: 1, bottom: 2, trailing: 1))
        .contextMenu {
            Button {
                viewModel.addSubfolder(parentFolderID: folder.id)
            } label: {
                Text("New Folder")
            }

            Button {
                viewModel.startRenameFolder(folderID: folder.id)
            } label: {
                Text("Rename Folder")
            }

            Button(role: .destructive) {
                viewModel.deleteFolder(folderID: folder.id)
            } label: {
                Text("Delete Folder")
            }
        }
    }
}
