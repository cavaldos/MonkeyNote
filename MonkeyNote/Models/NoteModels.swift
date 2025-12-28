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
    var createdAt: Date
    var isTitleCustom: Bool
    var savedTitle: String
    var isPinned: Bool
    
    // Large file protection
    var isTooLarge: Bool
    var lineCount: Int

    init(
        id: UUID = UUID(),
        title: String,
        text: String = "",
        updatedAt: Date = Date(),
        createdAt: Date = Date(),
        isTitleCustom: Bool = false,
        savedTitle: String? = nil,
        isPinned: Bool = false,
        isTooLarge: Bool = false,
        lineCount: Int = 0
    ) {
        self.id = id
        self.title = title
        self.text = text
        self.updatedAt = updatedAt
        self.createdAt = createdAt
        self.isTitleCustom = isTitleCustom
        self.savedTitle = savedTitle ?? title
        self.isPinned = isPinned
        self.isTooLarge = isTooLarge
        self.lineCount = lineCount
    }
    
    // Only save metadata to JSON, not text content (stored in .md files)
    enum CodingKeys: String, CodingKey {
        case id, title, updatedAt, createdAt, isTitleCustom, savedTitle, isPinned
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        title = try container.decode(String.self, forKey: .title)
        updatedAt = try container.decode(Date.self, forKey: .updatedAt)
        createdAt = try container.decodeIfPresent(Date.self, forKey: .createdAt) ?? Date() // Default for old data
        isTitleCustom = try container.decode(Bool.self, forKey: .isTitleCustom)
        savedTitle = try container.decode(String.self, forKey: .savedTitle)
        isPinned = try container.decodeIfPresent(Bool.self, forKey: .isPinned) ?? false // Default for old data
        text = "" // Will be loaded from .md file
        isTooLarge = false // Will be determined when loading .md file
        lineCount = 0 // Will be determined when loading .md file
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(title, forKey: .title)
        try container.encode(updatedAt, forKey: .updatedAt)
        try container.encode(createdAt, forKey: .createdAt)
        try container.encode(isTitleCustom, forKey: .isTitleCustom)
        try container.encode(savedTitle, forKey: .savedTitle)
        try container.encode(isPinned, forKey: .isPinned)
        // text, isTooLarge, lineCount are NOT encoded - determined at runtime
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

// MARK: - Sort Options

enum NoteSortOption: String, CaseIterable, Codable {
    case nameAscending = "Name A-Z"
    case nameDescending = "Name Z-A"
    case dateNewest = "Date Newest"
    case dateOldest = "Date Oldest"
    case createdNewest = "Created Newest"
    case createdOldest = "Created Oldest"
    
    var icon: String {
        switch self {
        case .nameAscending: return "textformat.abc"
        case .nameDescending: return "textformat.abc"
        case .dateNewest, .dateOldest: return "clock"
        case .createdNewest, .createdOldest: return "calendar"
        }
    }
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
