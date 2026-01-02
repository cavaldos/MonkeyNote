//
//  StatusBarView.swift
//  MonkeyNote
//
//  Created by Assistant on 03/01/26.
//

import SwiftUI

struct StatusBarView: View {
    @Environment(ContentViewModel.self) var viewModel
    
    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "doc.text")
                .font(.system(size: 12, weight: .regular))
            Text("\(viewModel.wordCount) words")
            Text("|")
            Image(systemName: "text.alignleft")
                .font(.system(size: 12, weight: .regular))
            Text("\(viewModel.lineCount) lines")
            Text("|")
            Image(systemName: "character.cursor.ibeam")
                .font(.system(size: 12, weight: .regular))
            Text("\(viewModel.characterCount) chars")
        }
        .font(.system(.footnote, design: .monospaced))
        .foregroundStyle(viewModel.isDarkMode ? .white.opacity(0.45) : .black.opacity(0.55))
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(viewModel.isDarkMode ? Color.white.opacity(0.06) : Color.black.opacity(0.06))
        )
    }
}
