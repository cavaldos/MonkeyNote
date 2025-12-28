//
//  DemoMode.swift
//  MonkeyNote
//
//  Created by Assistant on 28/12/24.
//

import Foundation
import Combine

// MARK: - Demo Mode Manager
/// Manages demo/fake typing mode for video recording
class DemoModeManager: ObservableObject {
    static let shared = DemoModeManager()
    
    /// Whether demo mode is enabled
    @Published var isEnabled: Bool = false
    
    /// The pre-defined text to type
    @Published var demoText: String = ""
    
    /// Current position in the demo text
    private var currentIndex: Int = 0
    
    private init() {}
    
    // MARK: - Public Methods
    
    /// Set the demo text and reset position
    func setDemoText(_ text: String) {
        demoText = text
        currentIndex = 0
    }
    
    /// Enable demo mode with the given text
    func enable(with text: String) {
        setDemoText(text)
        isEnabled = true
    }
    
    /// Disable demo mode
    func disable() {
        isEnabled = false
        currentIndex = 0
    }
    
    /// Toggle demo mode
    func toggle() {
        if isEnabled {
            disable()
        } else {
            isEnabled = true
        }
    }
    
    /// Get the next character(s) to insert
    /// Returns nil if demo text is exhausted
    func getNextCharacter() -> String? {
        guard isEnabled, currentIndex < demoText.count else {
            return nil
        }
        
        let index = demoText.index(demoText.startIndex, offsetBy: currentIndex)
        let char = String(demoText[index])
        currentIndex += 1
        
        return char
    }
    
    /// Get next word or chunk (for faster typing simulation)
    func getNextWord() -> String? {
        guard isEnabled, currentIndex < demoText.count else {
            return nil
        }
        
        let startIndex = demoText.index(demoText.startIndex, offsetBy: currentIndex)
        let remaining = String(demoText[startIndex...])
        
        // Find the end of current word (space or newline)
        if let spaceIndex = remaining.firstIndex(where: { $0 == " " || $0 == "\n" }) {
            let word = String(remaining[..<remaining.index(after: spaceIndex)])
            currentIndex += word.count
            return word
        } else {
            // Return the rest
            currentIndex = demoText.count
            return remaining
        }
    }
    
    /// Reset the demo text position to start
    func reset() {
        currentIndex = 0
    }
    
    /// Check if there's more text to type
    var hasMoreText: Bool {
        return currentIndex < demoText.count
    }
    
    /// Get remaining text count
    var remainingCount: Int {
        return max(0, demoText.count - currentIndex)
    }
    
    /// Get progress (0.0 to 1.0)
    var progress: Double {
        guard demoText.count > 0 else { return 0 }
        return Double(currentIndex) / Double(demoText.count)
    }
    
    /// Handle backspace - go back one character in demo text
    func handleBackspace() -> Bool {
        guard isEnabled, currentIndex > 0 else {
            return false
        }
        currentIndex -= 1
        return true
    }
}
