//
//  ThickCursorTextEditor.swift
//  Note
//
//  Created by Nguyen Ngoc Khanh on 24/12/25.
//

#if os(macOS)
import SwiftUI
import AppKit

private class ThickCursorLayoutManager: NSLayoutManager {
    var cursorWidth: CGFloat = 6
}

private class ThickCursorTextView: NSTextView {
    var cursorWidth: CGFloat = 6
    var cursorAnimationEnabled: Bool = true
    var cursorAnimationDuration: Double = 0.15
    var searchText: String = ""
    private var cursorLayer: CALayer?
    private var lastCursorRect: NSRect = .zero
    private var highlightLayers: [CALayer] = []

    override func drawInsertionPoint(in rect: NSRect, color: NSColor, turnedOn flag: Bool) {
        guard flag else {
            cursorLayer?.opacity = 0
            return
        }

        var thickRect = rect
        thickRect.size.width = cursorWidth

        if cursorLayer == nil {
            let layer = CALayer()
            layer.cornerRadius = cursorWidth / 2
            layer.backgroundColor = color.cgColor
            wantsLayer = true
            self.layer?.addSublayer(layer)
            cursorLayer = layer
        }

        cursorLayer?.backgroundColor = color.cgColor
        cursorLayer?.cornerRadius = cursorWidth / 2

        if lastCursorRect != thickRect {
            if cursorAnimationEnabled {
                CATransaction.begin()
                CATransaction.setAnimationDuration(cursorAnimationDuration)
                CATransaction.setAnimationTimingFunction(CAMediaTimingFunction(name: .easeOut))
                cursorLayer?.frame = thickRect
                cursorLayer?.opacity = 1
                CATransaction.commit()
            } else {
                cursorLayer?.frame = thickRect
                cursorLayer?.opacity = 1
            }
            lastCursorRect = thickRect
        } else {
            cursorLayer?.frame = thickRect
            cursorLayer?.opacity = 1
        }
    }

    override func setNeedsDisplay(_ invalidRect: NSRect, avoidAdditionalLayout flag: Bool) {
        var extendedRect = invalidRect
        extendedRect.size.width += cursorWidth
        super.setNeedsDisplay(extendedRect, avoidAdditionalLayout: flag)
    }

    override var rangeForUserCompletion: NSRange {
        selectedRange()
    }

    func updateHighlights() {
        self.highlightLayers.forEach { $0.removeFromSuperlayer() }
        self.highlightLayers.removeAll()

        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty, let layoutManager = layoutManager, let textContainer = textContainer else { return }

        let text = self.string
        var searchRange = NSRange(location: 0, length: text.utf16.count)

        while searchRange.location < text.utf16.count {
            let foundRange = (text as NSString).range(of: query, options: .caseInsensitive, range: searchRange)

            if foundRange.location == NSNotFound {
                break
            }

            let glyphRange = layoutManager.glyphRange(forCharacterRange: foundRange, actualCharacterRange: nil)
            layoutManager.enumerateEnclosingRects(forGlyphRange: glyphRange, withinSelectedGlyphRange: glyphRange, in: textContainer) { rect, _ in
                let highlightLayer = CALayer()
                highlightLayer.backgroundColor = NSColor.yellow.withAlphaComponent(0.3).cgColor
                highlightLayer.cornerRadius = 2
                highlightLayer.frame = rect
                self.layer?.addSublayer(highlightLayer)
                self.highlightLayers.append(highlightLayer)
            }

            searchRange.location = foundRange.location + foundRange.length
            searchRange.length = text.utf16.count - searchRange.location
        }
    }

    override func keyDown(with event: NSEvent) {
        guard !event.isARepeat else {
            super.keyDown(with: event)
            return
        }
        
        if event.keyCode == 48 {
            let selectedRange = self.selectedRange()
            let text = self.string as NSString
            
            // Check if character BEFORE cursor is "-"
            if selectedRange.location > 0 {
                let prevCharIndex = selectedRange.location - 1
                if prevCharIndex < text.length {
                    let prevChar = text.substring(with: NSRange(location: prevCharIndex, length: 1))
                    if prevChar == "-" {
                        // Get the rest of the line after the dash
                        let lineRange = text.lineRange(for: NSRange(location: prevCharIndex, length: 0))
                        let rangeAfterDash = NSRange(location: prevCharIndex + 1, length: lineRange.location + lineRange.length - prevCharIndex - 1)
                        let remainingText = text.substring(with: rangeAfterDash)
                        
                        // Replace the entire line from dash to end with bullet + remaining text
                        let lineAfterDash = NSRange(location: prevCharIndex, length: lineRange.location + lineRange.length - prevCharIndex)
                        let newText = "• " + remainingText.trimmingCharacters(in: .whitespacesAndNewlines)
                        self.replaceCharacters(in: lineAfterDash, with: newText)
                        self.setSelectedRange(NSRange(location: prevCharIndex + newText.utf16.count, length: 0))
                        return
                    }
                    
                    // Check for numbered list pattern like "1."
                    if prevCharIndex >= 1 {
                        let twoCharsBefore = text.substring(with: NSRange(location: prevCharIndex - 1, length: 2))
                        if let regex = try? NSRegularExpression(pattern: "^\\d\\.", options: []),
                           regex.firstMatch(in: twoCharsBefore, options: [], range: NSRange(location: 0, length: 2)) != nil {
                            let lineRange = text.lineRange(for: NSRange(location: prevCharIndex - 1, length: 0))
                            let rangeAfterNumber = NSRange(location: prevCharIndex + 1, length: lineRange.location + lineRange.length - prevCharIndex - 1)
                            let remainingText = text.substring(with: rangeAfterNumber)
                            
                            // Replace the entire line from number to end with proper numbered list format
                            let lineAfterNumber = NSRange(location: prevCharIndex - 1, length: lineRange.location + lineRange.length - (prevCharIndex - 1))
                            let newText = twoCharsBefore + " " + remainingText.trimmingCharacters(in: .whitespacesAndNewlines)
                            self.replaceCharacters(in: lineAfterNumber, with: newText)
                            self.setSelectedRange(NSRange(location: prevCharIndex - 1 + newText.utf16.count, length: 0))
                            return
                        }
                    }
                }
            }
            
            super.insertText("\t")
            return
        }
        
        if event.keyCode == 36 {
            let selectedRange = self.selectedRange()
            let text = self.string as NSString
            
            let lineRange = text.lineRange(for: selectedRange)
            let currentLine = text.substring(with: lineRange)
            let trimmedLine = currentLine.trimmingCharacters(in: .whitespaces)
            
            if trimmedLine.hasPrefix("• ") {
                let bulletContent = trimmedLine.dropFirst("• ".count).trimmingCharacters(in: .whitespaces)
                
                if bulletContent.isEmpty {
                    let linesBefore = text.substring(with: NSRange(location: 0, length: lineRange.location))
                    let linesAfter = text.substring(with: NSRange(location: lineRange.location + lineRange.length, length: text.length - (lineRange.location + lineRange.length)))
                    let newString = linesBefore + linesAfter
                    self.string = newString
                    self.setSelectedRange(NSRange(location: lineRange.location, length: 0))
                } else {
                    super.insertText("\n• ")
                    self.setSelectedRange(NSRange(location: selectedRange.location + "\n• ".utf16.count, length: 0))
                }
                return
            }
            
            // Handle numbered list
            if let regex = try? NSRegularExpression(pattern: "^(\\d+)\\.", options: []),
               let match = regex.firstMatch(in: trimmedLine, options: [], range: NSRange(location: 0, length: trimmedLine.utf16.count)) {
                let numberRange = match.range(at: 1)
                let numberString = (trimmedLine as NSString).substring(with: numberRange)
                let number = Int(numberString) ?? 1
                let contentStart = match.range.location + match.range.length
                let contentLength = trimmedLine.utf16.count - contentStart
                let content = (trimmedLine as NSString).substring(with: NSRange(location: contentStart, length: contentLength)).trimmingCharacters(in: .whitespaces)
                
                if content.isEmpty {
                    let linesBefore = text.substring(with: NSRange(location: 0, length: lineRange.location))
                    let linesAfter = text.substring(with: NSRange(location: lineRange.location + lineRange.length, length: text.length - (lineRange.location + lineRange.length)))
                    let newString = linesBefore + linesAfter
                    self.string = newString
                    self.setSelectedRange(NSRange(location: lineRange.location, length: 0))
                } else {
                    let nextNumber = number + 1
                    let nextLineText = "\n\(nextNumber). "
                    super.insertText(nextLineText)
                    self.setSelectedRange(NSRange(location: selectedRange.location + nextLineText.utf16.count, length: 0))
                }
                return
            }
        }
        
        super.keyDown(with: event)
    }
    
    override func layout() {
        super.layout()
        updateHighlights()
    }
}

struct ThickCursorTextEditor: NSViewRepresentable {
    @Binding var text: String
    var isDarkMode: Bool
    var cursorWidth: CGFloat
    var cursorAnimationEnabled: Bool
    var cursorAnimationDuration: Double
    var fontSize: Double
    var fontFamily: String
    var searchText: String

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.borderType = .noBorder
        scrollView.drawsBackground = false

        let layoutManager = ThickCursorLayoutManager()
        layoutManager.cursorWidth = cursorWidth

        let textStorage = NSTextStorage()
        textStorage.addLayoutManager(layoutManager)

        let textContainer = NSTextContainer()
        textContainer.widthTracksTextView = true
        textContainer.containerSize = NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude)
        layoutManager.addTextContainer(textContainer)

        let textView = ThickCursorTextView(frame: .zero, textContainer: textContainer)
        textView.cursorWidth = cursorWidth
        textView.cursorAnimationEnabled = cursorAnimationEnabled
        textView.cursorAnimationDuration = cursorAnimationDuration
        textView.searchText = searchText
        textView.isRichText = false
        textView.allowsUndo = true
        textView.isEditable = true
        textView.isSelectable = true
        textView.drawsBackground = false
        textView.textContainerInset = NSSize(width: 0, height: 0)
        
        // Critical settings for proper scrolling
        textView.minSize = NSSize(width: 0, height: 0)
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]

        let font: NSFont
        switch fontFamily {
        case "rounded":
            font = NSFont.systemFont(ofSize: fontSize, weight: .regular)
        case "serif":
            font = NSFont(name: "Times New Roman", size: fontSize) ?? NSFont.systemFont(ofSize: fontSize, weight: .regular)
        default:
            if let customFont = NSFont(name: fontFamily, size: fontSize) {
                font = customFont
            } else {
                font = NSFont.monospacedSystemFont(ofSize: fontSize, weight: .regular)
            }
        }
        textView.font = font
        textView.textColor = isDarkMode
            ? NSColor.white.withAlphaComponent(0.92)
            : NSColor.black.withAlphaComponent(0.92)
        textView.insertionPointColor = NSColor(
            red: 222.0 / 255.0,
            green: 99.0 / 255.0,
            blue: 74.0 / 255.0,
            alpha: 1.0
        )

        textView.delegate = context.coordinator
        textView.string = text

        scrollView.documentView = textView
        context.coordinator.textView = textView

        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? ThickCursorTextView else { return }

        if textView.string != text {
            let selectedRange = textView.selectedRange()
            textView.string = text
            let safeLocation = min(selectedRange.location, text.utf16.count)
            let safeLength = min(selectedRange.length, text.utf16.count - safeLocation)
            textView.setSelectedRange(NSRange(location: safeLocation, length: safeLength))
        }

        textView.cursorWidth = cursorWidth
        textView.cursorAnimationEnabled = cursorAnimationEnabled
        textView.cursorAnimationDuration = cursorAnimationDuration
        textView.searchText = searchText
        if let layoutManager = textView.layoutManager as? ThickCursorLayoutManager {
            layoutManager.cursorWidth = cursorWidth
        }

        let font: NSFont
        switch fontFamily {
        case "rounded":
            font = NSFont.systemFont(ofSize: fontSize, weight: .regular)
        case "serif":
            font = NSFont(name: "Times New Roman", size: fontSize) ?? NSFont.systemFont(ofSize: fontSize, weight: .regular)
        default:
            if let customFont = NSFont(name: fontFamily, size: fontSize) {
                font = customFont
            } else {
                font = NSFont.monospacedSystemFont(ofSize: fontSize, weight: .regular)
            }
        }
        textView.font = font

        textView.textColor = isDarkMode
            ? NSColor.white.withAlphaComponent(0.92)
            : NSColor.black.withAlphaComponent(0.92)
        textView.insertionPointColor = NSColor(
            red: 222.0 / 255.0,
            green: 99.0 / 255.0,
            blue: 74.0 / 255.0,
            alpha: 1.0
        )

        textView.updateHighlights()
    }

    class Coordinator: NSObject, NSTextViewDelegate {
        var parent: ThickCursorTextEditor
        fileprivate weak var textView: ThickCursorTextView?

        init(_ parent: ThickCursorTextEditor) {
            self.parent = parent
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            parent.text = textView.string
            
            // Auto-scroll to cursor position with smooth animation
            guard let scrollView = textView.enclosingScrollView,
                  let layoutManager = textView.layoutManager,
                  let textContainer = textView.textContainer else { return }
            
            let selectedRange = textView.selectedRange()
            let glyphRange = layoutManager.glyphRange(forCharacterRange: selectedRange, actualCharacterRange: nil)
            let cursorRect = layoutManager.boundingRect(forGlyphRange: glyphRange, in: textContainer)
            
            let cursorY = cursorRect.origin.y + textView.textContainerInset.height
            let cursorHeight = max(cursorRect.height, textView.font?.pointSize ?? 16)
            let visibleRect = scrollView.documentVisibleRect
            let padding: CGFloat = 20
            
            // Check if cursor is below visible area
            if cursorY + cursorHeight > visibleRect.maxY - padding {
                let newY = cursorY + cursorHeight - visibleRect.height + padding
                let targetPoint = NSPoint(x: 0, y: max(0, newY))
                
                NSAnimationContext.runAnimationGroup { context in
                    context.duration = 0.15
                    context.timingFunction = CAMediaTimingFunction(name: .easeOut)
                    scrollView.contentView.animator().setBoundsOrigin(targetPoint)
                }
            }
            // Check if cursor is above visible area
            else if cursorY < visibleRect.minY + padding {
                let targetPoint = NSPoint(x: 0, y: max(0, cursorY - padding))
                
                NSAnimationContext.runAnimationGroup { context in
                    context.duration = 0.15
                    context.timingFunction = CAMediaTimingFunction(name: .easeOut)
                    scrollView.contentView.animator().setBoundsOrigin(targetPoint)
                }
            }
        }
    }
}
#endif
