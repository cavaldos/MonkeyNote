//
//  SelectionToolbarFeature.swift
//  MonkeyNote
//
//  Extension for selection toolbar functionality
//

#if os(macOS)
import AppKit

// MARK: - Selection Toolbar
extension CursorTextView {
    
    func handleSelectionChange() {
        let selectedRange = self.selectedRange()
        
        // Hide autocomplete suggestion when cursor moves
        hideSuggestion()
        
        // Update cursor position in MarkdownTextStorage for syntax visibility
        if let textStorage = self.textStorage as? MarkdownTextStorage {
            textStorage.cursorPosition = selectedRange.location
        }
        
        // Show selection toolbar when there's a selection (but not during search navigation)
        if selectedRange.length > 0 && !isNavigatingSearch {
            showSelectionToolbar(for: selectedRange)
        } else {
            selectionToolbarController.dismiss()
        }
    }
    
    func showSelectionToolbar(for range: NSRange) {
        guard let layoutManager = layoutManager,
              let textContainer = textContainer,
              let window = self.window else { return }
        
        // Get the rect of the selected text
        let glyphRange = layoutManager.glyphRange(forCharacterRange: range, actualCharacterRange: nil)
        var selectionRect = layoutManager.boundingRect(forGlyphRange: glyphRange, in: textContainer)
        selectionRect.origin.x += textContainerInset.width
        selectionRect.origin.y += textContainerInset.height
        
        // Convert to window coordinates
        let rectInView = convert(selectionRect, to: nil)
        let rectInScreen = window.convertToScreen(NSRect(
            origin: rectInView.origin,
            size: CGSize(width: selectionRect.width, height: selectionRect.height)
        ))
        
        // Position toolbar above the selection (centered)
        let toolbarPoint = NSPoint(
            x: rectInScreen.midX,
            y: rectInScreen.maxY
        )
        
        selectionToolbarController.show(
            at: toolbarPoint,
            in: window,
            selectionRange: range,
            onAction: { [weak self] (action: ToolbarAction, selectionRange: NSRange) in
                self?.applyFormatting(action: action, range: selectionRange)
            }
        )
    }
}
#endif
