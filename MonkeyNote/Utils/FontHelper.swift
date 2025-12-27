//
//  FontHelper.swift
//  MonkeyNote
//
//  Created by Nguyen Ngoc Khanh on 27/12/25.
//

import SwiftUI

enum FontHelper {

    static func getFontDesign(from fontFamily: String) -> Font.Design {
        switch fontFamily {
        case "rounded": return .rounded
        case "serif": return .serif
        default: return .monospaced
        }
    }
}
