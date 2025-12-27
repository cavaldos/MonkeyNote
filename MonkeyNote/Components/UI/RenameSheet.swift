//
//  RenameSheet.swift
//  Note
//
//  Created by Nguyen Ngoc Khanh on 24/12/25.
//

import SwiftUI

struct RenameSheet: View {
    let title: String
    let placeholder: String
    let onCancel: () -> Void
    let onSave: (String) -> Void

    @State private var text: String

    init(
        title: String,
        placeholder: String,
        initialText: String,
        onCancel: @escaping () -> Void,
        onSave: @escaping (String) -> Void
    ) {
        self.title = title
        self.placeholder = placeholder
        self.onCancel = onCancel
        self.onSave = onSave
        _text = State(initialValue: initialText)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.headline)

            TextField(placeholder, text: $text)
                .textFieldStyle(.roundedBorder)

            HStack {
                Spacer()
                Button("Cancel") { onCancel() }
                Button("Save") { onSave(text) }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(16)
        .frame(width: 360)
    }
}
