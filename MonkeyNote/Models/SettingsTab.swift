//
//  SettingsTab.swift
//  MonkeyNote
//
//  Created by Nguyen Ngoc Khanh on 27/12/25.
//

import Foundation

enum SettingsTab: String, CaseIterable {
    case vault = "Vault"
    case appearance = "Appearance"
    case autocomplete = "Autocomplete"
    case keyboard = "Keyboard"
    case about = "About"

    var icon: String {
        switch self {
        case .vault: return "folder.fill"
        case .appearance: return "paintbrush"
        case .autocomplete: return "text.cursor"
        case .keyboard: return "keyboard"
        case .about: return "info.circle"
        }
    }
}
