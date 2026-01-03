//
//  FocusableSearchField.swift
//  MonkeyNote
//
//  Created by Assistant on 03/01/26.
//

import SwiftUI

#if os(macOS)
import AppKit

struct FocusableSearchField: NSViewRepresentable {
    @Binding var text: String
    var onSubmit: (() -> Void)? = nil
    var onEscape: (() -> Void)? = nil
    
    func makeNSView(context: Context) -> NSTextField {
        let textField = NSTextField()
        textField.placeholderString = "Search"
        textField.isBordered = false
        textField.backgroundColor = .clear
        textField.font = .systemFont(ofSize: 12)
        textField.focusRingType = .none
        textField.delegate = context.coordinator
        
        // Listen for focusSearch notification (no text)
        NotificationCenter.default.addObserver(
            context.coordinator,
            selector: #selector(Coordinator.focusTextField),
            name: .focusSearch,
            object: nil
        )
        
        // Listen for focusSearchWithText notification (with selected text)
        NotificationCenter.default.addObserver(
            context.coordinator,
            selector: #selector(Coordinator.focusTextFieldWithText(_:)),
            name: .focusSearchWithText,
            object: nil
        )
        
        context.coordinator.textField = textField
        
        return textField
    }
    
    func updateNSView(_ nsView: NSTextField, context: Context) {
        if nsView.stringValue != text {
            nsView.stringValue = text
        }
        context.coordinator.onSubmit = onSubmit
        context.coordinator.onEscape = onEscape
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text, onSubmit: onSubmit, onEscape: onEscape)
    }
    
    class Coordinator: NSObject, NSTextFieldDelegate {
        @Binding var text: String
        weak var textField: NSTextField?
        var onSubmit: (() -> Void)?
        var onEscape: (() -> Void)?
        
        init(text: Binding<String>, onSubmit: (() -> Void)?, onEscape: (() -> Void)?) {
            _text = text
            self.onSubmit = onSubmit
            self.onEscape = onEscape
        }
        
        @objc func focusTextField() {
            DispatchQueue.main.async {
                self.textField?.window?.makeFirstResponder(self.textField)
            }
        }
        
        @objc func focusTextFieldWithText(_ notification: Notification) {
            DispatchQueue.main.async {
                // Get selected text from notification
                if let selectedText = notification.userInfo?["text"] as? String {
                    self.text = selectedText
                    self.textField?.stringValue = selectedText
                }
                self.textField?.window?.makeFirstResponder(self.textField)
                // Select all text in the search field
                self.textField?.selectText(nil)
            }
        }
        
        func controlTextDidChange(_ obj: Notification) {
            if let textField = obj.object as? NSTextField {
                text = textField.stringValue
            }
        }
        
        func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
            if commandSelector == #selector(NSResponder.insertNewline(_:)) {
                // Enter key pressed
                onSubmit?()
                return true
            } else if commandSelector == #selector(NSResponder.cancelOperation(_:)) {
                // ESC key pressed - unfocus and return focus to editor
                textField?.window?.makeFirstResponder(nil)
                onEscape?()
                // Post notification to focus editor
                NotificationCenter.default.post(name: .focusEditor, object: nil)
                return true
            }
            return false
        }
    }
}
#endif
