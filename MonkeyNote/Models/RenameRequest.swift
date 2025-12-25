//
//  RenameRequest.swift
//  Note
//
//  Created by Nguyen Ngoc Khanh on 24/12/25.
//

import Foundation

struct RenameRequest: Identifiable {
    enum Kind {
        case folder(NoteFolder.ID)
        case note(folderID: NoteFolder.ID, noteID: NoteItem.ID)
    }

    let id = UUID()
    let kind: Kind
    let title: String
    let placeholder: String
    let initialText: String
}
