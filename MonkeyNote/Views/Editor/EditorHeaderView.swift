//
//  EditorHeaderView.swift
//  MonkeyNote
//
//  Created by Assistant on 03/01/26.
//

import SwiftUI

struct EditorHeaderView: View {
    @Environment(ContentViewModel.self) var viewModel
    
    var body: some View {
        HStack(spacing: 8) {
            // Close button for external file
            if viewModel.isEditingExternalFile {
                Button {
                    viewModel.closeExternalFile()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("Close external file")
            }
            
            Text(viewModel.selectedNoteTitle)
            Circle()
                .fill(Color.red)
                .frame(width: 6, height: 6)
            
            // Show file path for external file
            if viewModel.isEditingExternalFile, let url = viewModel.externalFileURL {
                Text(viewModel.formatFilePath(url))
                    .font(.system(size: 10, weight: .regular, design: .monospaced))
                    .foregroundStyle(viewModel.isDarkMode ? .white.opacity(0.35) : .black.opacity(0.45))
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
        }
        .font(.system(.body, design: .monospaced))
        .foregroundStyle(viewModel.isDarkMode ? .white.opacity(0.45) : .black.opacity(0.55))
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
