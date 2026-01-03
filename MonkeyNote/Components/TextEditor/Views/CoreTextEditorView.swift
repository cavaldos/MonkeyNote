//
//  CoreTextEditorView.swift
//  MonkeyNote
//
//  SwiftUI wrapper for CoreTextView.
//  Provides a native SwiftUI interface for the CoreText-based editor.
//

#if os(macOS)
import SwiftUI
import AppKit

/// SwiftUI wrapper for the CoreText-based editor
struct CoreTextEditorView: NSViewRepresentable {
    
    // MARK: - Bindings
    
    @Binding var text: String
    
    // MARK: - Configuration
    
    var isDarkMode: Bool = false
    var cursorWidth: CGFloat = 6
    var cursorBlinkEnabled: Bool = true
    var cursorAnimationEnabled: Bool = true
    var cursorAnimationDuration: Double = 0.15
    var fontSize: Double = 14
    var fontFamily: String = "monospace"
    var horizontalPadding: CGFloat = 8
    var lineSpacing: CGFloat = 0
    
    // MARK: - Search
    
    var searchText: String = ""
    var currentSearchIndex: Int = 0
    var onSearchMatchesChanged: ((Int, Bool) -> Void)? = nil
    
    // MARK: - Callbacks
    
    var onTextChange: ((String) -> Void)? = nil
    
    // MARK: - NSViewRepresentable
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    func makeNSView(context: Context) -> NSScrollView {
        // Create scroll view
        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.borderType = .noBorder
        scrollView.drawsBackground = false
        
        // Create CoreTextView
        let coreTextView = CoreTextView(frame: .zero)
        coreTextView.delegate = context.coordinator
        
        // Configure appearance
        coreTextView.font = makeFont()
        coreTextView.isDarkMode = isDarkMode
        coreTextView.cursorWidth = cursorWidth
        coreTextView.cursorBlinkEnabled = cursorBlinkEnabled
        coreTextView.cursorAnimationEnabled = cursorAnimationEnabled
        coreTextView.cursorAnimationDuration = cursorAnimationDuration
        coreTextView.textInsets = NSEdgeInsets(top: 8, left: horizontalPadding, bottom: 8, right: horizontalPadding)
        coreTextView.lineSpacing = lineSpacing
        
        // Set initial text
        coreTextView.string = text
        
        // Configure scroll view
        scrollView.documentView = coreTextView
        context.coordinator.coreTextView = coreTextView
        
        return scrollView
    }
    
    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let coreTextView = context.coordinator.coreTextView else { return }
        
        // Update text if changed externally
        if coreTextView.string != text {
            coreTextView.string = text
        }
        
        // Update appearance
        coreTextView.font = makeFont()
        coreTextView.isDarkMode = isDarkMode
        coreTextView.cursorWidth = cursorWidth
        coreTextView.cursorBlinkEnabled = cursorBlinkEnabled
        coreTextView.cursorAnimationEnabled = cursorAnimationEnabled
        coreTextView.cursorAnimationDuration = cursorAnimationDuration
        coreTextView.textInsets = NSEdgeInsets(top: 8, left: horizontalPadding, bottom: 8, right: horizontalPadding)
        coreTextView.lineSpacing = lineSpacing
        
        // Update layout config
        coreTextView.layoutEngine.config.containerWidth = scrollView.contentSize.width
    }
    
    // MARK: - Helpers
    
    private func makeFont() -> NSFont {
        switch fontFamily {
        case "rounded":
            return NSFont.systemFont(ofSize: fontSize, weight: .regular)
        case "serif":
            return NSFont(name: "Times New Roman", size: fontSize) 
                ?? NSFont.systemFont(ofSize: fontSize, weight: .regular)
        case "monospace":
            return NSFont.monospacedSystemFont(ofSize: fontSize, weight: .regular)
        default:
            if let customFont = NSFont(name: fontFamily, size: fontSize) {
                return customFont
            }
            return NSFont.monospacedSystemFont(ofSize: fontSize, weight: .regular)
        }
    }
    
    // MARK: - Coordinator
    
    class Coordinator: NSObject, CoreTextViewDelegate {
        var parent: CoreTextEditorView
        weak var coreTextView: CoreTextView?
        
        init(_ parent: CoreTextEditorView) {
            self.parent = parent
            super.init()
            
            // Listen for focus editor notification
            NotificationCenter.default.addObserver(
                self,
                selector: #selector(focusEditor),
                name: Notification.Name("focusEditor"),
                object: nil
            )
        }
        
        deinit {
            NotificationCenter.default.removeObserver(self)
        }
        
        @objc func focusEditor() {
            DispatchQueue.main.async {
                self.coreTextView?.window?.makeFirstResponder(self.coreTextView)
            }
        }
        
        // MARK: - CoreTextViewDelegate
        
        func coreTextViewTextDidChange(_ view: CoreTextView) {
            parent.text = view.string
            parent.onTextChange?(view.string)
        }
        
        func coreTextViewSelectionDidChange(_ view: CoreTextView) {
            // Handle selection changes if needed
        }
    }
}

// MARK: - Preview

#if DEBUG
struct CoreTextEditorView_Previews: PreviewProvider {
    static var previews: some View {
        CoreTextEditorView(
            text: .constant("Hello, World!\nThis is a test.\n\nMultiple paragraphs here."),
            isDarkMode: false,
            fontSize: 14
        )
        .frame(width: 400, height: 300)
    }
}
#endif

#endif
