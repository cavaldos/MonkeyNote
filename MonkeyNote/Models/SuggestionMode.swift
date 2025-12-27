//
//  SuggestionMode.swift
//  MonkeyNote
//
//  Created by Nguyen Ngoc Khanh on 27/12/25.
//

import Foundation

enum SuggestionMode: String, CaseIterable {
    case word = "word"
    case sentence = "sentence"

    var displayName: String {
        switch self {
        case .word: return "Word"
        case .sentence: return "Sentence"
        }
    }

    var icon: String {
        switch self {
        case .word: return "textformat.abc"
        case .sentence: return "text.quote"
        }
    }
}
