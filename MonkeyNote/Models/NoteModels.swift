//
//  NoteModels.swift
//  Note
//
//  Created by Nguyen Ngoc Khanh on 24/12/25.
//

import Foundation

struct NoteItem: Identifiable, Hashable, Codable {
    let id: UUID
    var title: String
    var text: String
    var updatedAt: Date
    var isTitleCustom: Bool
    var savedTitle: String

    init(
        id: UUID = UUID(),
        title: String,
        text: String = "",
        updatedAt: Date = Date(),
        isTitleCustom: Bool = false,
        savedTitle: String? = nil
    ) {
        self.id = id
        self.title = title
        self.text = text
        self.updatedAt = updatedAt
        self.isTitleCustom = isTitleCustom
        self.savedTitle = savedTitle ?? title
    }
    
    // Only save metadata to JSON, not text content (stored in .md files)
    enum CodingKeys: String, CodingKey {
        case id, title, updatedAt, isTitleCustom, savedTitle
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        title = try container.decode(String.self, forKey: .title)
        updatedAt = try container.decode(Date.self, forKey: .updatedAt)
        isTitleCustom = try container.decode(Bool.self, forKey: .isTitleCustom)
        savedTitle = try container.decode(String.self, forKey: .savedTitle)
        text = "" // Will be loaded from .md file
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(title, forKey: .title)
        try container.encode(updatedAt, forKey: .updatedAt)
        try container.encode(isTitleCustom, forKey: .isTitleCustom)
        try container.encode(savedTitle, forKey: .savedTitle)
        // text is NOT encoded - stored in .md file
    }
}

struct NoteFolder: Identifiable, Hashable, Codable {
    let id: UUID
    var name: String
    var savedName: String
    var notes: [NoteItem]
    var children: [NoteFolder]

    var outlineChildren: [NoteFolder]? {
        children.isEmpty ? nil : children
    }

    init(
        id: UUID = UUID(),
        name: String,
        savedName: String? = nil,
        notes: [NoteItem] = [],
        children: [NoteFolder] = []
    ) {
        self.id = id
        self.name = name
        self.savedName = savedName ?? name
        self.notes = notes
        self.children = children
    }
    
    // Codable - exclude computed property
    enum CodingKeys: String, CodingKey {
        case id, name, savedName, notes, children
    }
}

// Wrapper for saving entire vault structure
struct VaultData: Codable {
    var folders: [NoteFolder]
    var version: Int = 1
}

// MARK: - Trash Items

enum TrashItemType: Hashable {
    case file
    case folder
}

struct TrashItem: Identifiable, Hashable {
    let id: UUID
    let name: String
    let type: TrashItemType
    let relativePath: String  // Path relative to vault root
    let fullURL: URL
    
    init(name: String, type: TrashItemType, relativePath: String, fullURL: URL) {
        self.id = UUID()
        self.name = name
        self.type = type
        self.relativePath = relativePath
        self.fullURL = fullURL
    }
}
