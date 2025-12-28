//
//  CustomColors.swift
//  MonkeyNote
//
//  Created by Assistant on 28/12/24.
//

import SwiftUI

#if os(macOS)
import AppKit
#else
import UIKit
#endif

// MARK: - Custom Colors
struct CustomColors {
    
    // MARK: - Primary Colors
    
    /// Green: RGB(148, 214, 150)
    static let green = Color(red: 148/255, green: 214/255, blue: 150/255)
    
    /// Orange: RGB(234, 170, 84)
    static let orange = Color(red: 234/255, green: 170/255, blue: 84/255)
    
    /// Purple: RGB(152, 125, 210)
    static let purple = Color(red: 152/255, green: 125/255, blue: 210/255)
    
    /// Blue: RGB(107, 154, 238)
    static let blue = Color(red: 107/255, green: 154/255, blue: 238/255)
    
    // MARK: - NSColor / UIColor variants
    
    #if os(macOS)
    static let nsGreen = NSColor(red: 148/255, green: 214/255, blue: 150/255, alpha: 1.0)
    static let nsOrange = NSColor(red: 234/255, green: 170/255, blue: 84/255, alpha: 1.0)
    static let nsPurple = NSColor(red: 152/255, green: 125/255, blue: 210/255, alpha: 1.0)
    static let nsBlue = NSColor(red: 107/255, green: 154/255, blue: 238/255, alpha: 1.0)
    #else
    static let uiGreen = UIColor(red: 148/255, green: 214/255, blue: 150/255, alpha: 1.0)
    static let uiOrange = UIColor(red: 234/255, green: 170/255, blue: 84/255, alpha: 1.0)
    static let uiPurple = UIColor(red: 152/255, green: 125/255, blue: 210/255, alpha: 1.0)
    static let uiBlue = UIColor(red: 107/255, green: 154/255, blue: 238/255, alpha: 1.0)
    #endif
}

// MARK: - Color Extension
extension Color {
    static let customGreen = CustomColors.green
    static let customOrange = CustomColors.orange
    static let customPurple = CustomColors.purple
    static let customBlue = CustomColors.blue
}

#if os(macOS)
// MARK: - NSColor Extension
extension NSColor {
    static let customGreen = CustomColors.nsGreen
    static let customOrange = CustomColors.nsOrange
    static let customPurple = CustomColors.nsPurple
    static let customBlue = CustomColors.nsBlue
}
#endif
