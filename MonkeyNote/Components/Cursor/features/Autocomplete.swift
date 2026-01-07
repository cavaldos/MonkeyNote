//
//  Autocomplete.swift
//  MonkeyNote
//
//  Extension for autocomplete ghost text suggestions
//

#if os(macOS)
import AppKit

// MARK: - Autocomplete Ghost Text
extension CursorTextView {
    
    func updateSuggestion() {
        // Check if autocomplete is enabled
        guard autocompleteEnabled else {
            hideSuggestion()
            return
        }
        
        // Cancel any pending suggestion task
        suggestionTask?.cancel()
        
        // Hide ghost text immediately when user types (no delay for hiding)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        ghostTextLayer?.isHidden = true
        CATransaction.commit()
        
        // If delay is 0, show immediately
        if autocompleteDelay <= 0 {
            performSuggestionUpdate()
        } else {
            // Debounce with delay
            suggestionTask = Task {
                try? await Task.sleep(nanoseconds: UInt64(autocompleteDelay * 1_000_000_000))
                guard !Task.isCancelled else { return }
                await MainActor.run {
                    performSuggestionUpdate()
                }
            }
        }
    }
    
    func performSuggestionUpdate() {
        let selectedRange = self.selectedRange()
        let text = self.string as NSString
        
        // Only suggest when cursor is at the end of a word (no selection)
        guard selectedRange.length == 0 else {
            hideSuggestion()
            return
        }
        
        let cursorPosition = selectedRange.location
        guard cursorPosition > 0 else {
            hideSuggestion()
            return
        }
        
        // Check suggestion mode
        if suggestionMode == "sentence" {
            // Sentence mode: always show beta message
            let suggestion = WordSuggestionManager.shared.getSentenceSuggestion()
            currentSuggestion = suggestion
            suggestionWordStart = cursorPosition
            showGhostText(suggestion, at: cursorPosition)
            return
        }
        
        // Word mode: find word and suggest completion
        // Find word start
        var wordStart = cursorPosition
        while wordStart > 0 {
            let charIndex = wordStart - 1
            let char = text.substring(with: NSRange(location: charIndex, length: 1))
            if char.rangeOfCharacter(from: CharacterSet.alphanumerics) == nil {
                break
            }
            wordStart -= 1
        }
        
        // Get the current word prefix
        let wordLength = cursorPosition - wordStart
        guard wordLength >= 2 else { // Only suggest after 2+ characters
            hideSuggestion()
            return
        }
        
        let currentWord = text.substring(with: NSRange(location: wordStart, length: wordLength))
        
        // Get suggestion
        if let suggestion = WordSuggestionManager.shared.getSuggestion(for: currentWord) {
            currentSuggestion = suggestion
            suggestionWordStart = wordStart
            showGhostText(suggestion, at: cursorPosition)
        } else {
            hideSuggestion()
        }
    }
    
    func showGhostText(_ text: String, at position: Int) {
        guard let layoutManager = layoutManager,
              let textContainer = textContainer else { return }
        
        // Get cursor position rect
        let glyphRange = layoutManager.glyphRange(forCharacterRange: NSRange(location: position, length: 0), actualCharacterRange: nil)
        var cursorRect = layoutManager.boundingRect(forGlyphRange: glyphRange, in: textContainer)
        cursorRect.origin.x += textContainerInset.width
        cursorRect.origin.y += textContainerInset.height
        
        // Create or update ghost text layer
        if ghostTextLayer == nil {
            let layer = CATextLayer()
            layer.contentsScale = NSScreen.main?.backingScaleFactor ?? 2.0
            layer.alignmentMode = .left
            wantsLayer = true
            self.layer?.addSublayer(layer)
            ghostTextLayer = layer
        }
        
        // Disable all animations for ghost text
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        
        // Configure the ghost text with opacity from settings
        let font = self.font ?? NSFont.systemFont(ofSize: 14)
        ghostTextLayer?.font = font
        ghostTextLayer?.fontSize = font.pointSize
        ghostTextLayer?.foregroundColor = NSColor.gray.withAlphaComponent(autocompleteOpacity).cgColor
        ghostTextLayer?.string = text
        
        // Calculate size for the ghost text
        let attributes: [NSAttributedString.Key: Any] = [.font: font]
        let textSize = (text as NSString).size(withAttributes: attributes)
        
        // Position ghost text right after cursor
        ghostTextLayer?.frame = NSRect(
            x: cursorRect.origin.x + cursorWidth,
            y: cursorRect.origin.y,
            width: textSize.width + 10,
            height: cursorRect.height
        )
        ghostTextLayer?.isHidden = false
        
        CATransaction.commit()
    }
    
    func hideSuggestion() {
        suggestionTask?.cancel()
        
        // Disable animation when hiding
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        ghostTextLayer?.isHidden = true
        CATransaction.commit()
        
        currentSuggestion = nil
    }
    
    func acceptSuggestion() -> Bool {
        guard let suggestion = currentSuggestion, !suggestion.isEmpty else {
            return false
        }
        
        // Insert the suggestion at cursor position
        let selectedRange = self.selectedRange()
        replaceCharacters(in: selectedRange, with: suggestion)
        
        // Move cursor to end of inserted text
        let newPosition = selectedRange.location + suggestion.utf16.count
        setSelectedRange(NSRange(location: newPosition, length: 0))
        
        hideSuggestion()
        return true
    }
}
#endif
