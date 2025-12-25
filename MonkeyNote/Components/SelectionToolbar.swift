//
//  SelectionToolbar.swift
//  MonkeyNote
//
//  Created by Assistant on 25/12/25.
//

#if os(macOS)
import SwiftUI
import AppKit

// MARK: - Toolbar Action
enum ToolbarAction: String, CaseIterable {
    case askAI = "Ask AI"
    case heading = "Aa"
    case bold = "B"
    case italic = "I"
    case code = "</>"
    case strikethrough = "S"
    case highlight = "Highlight"
    case link = "Link"
    case alignLeft = "Left"
    case list = "List"
    
    var icon: String {
        switch self {
        case .askAI: return "sparkles"
        case .heading: return "textformat.size"
        case .bold: return "bold"
        case .italic: return "italic"
        case .code: return "chevron.left.forwardslash.chevron.right"
        case .strikethrough: return "strikethrough"
        case .highlight: return "highlighter"
        case .link: return "link"
        case .alignLeft: return "text.alignleft"
        case .list: return "list.bullet"
        }
    }
    
    var markdownPrefix: String {
        switch self {
        case .bold: return "**"
        case .italic: return "_"
        case .code: return "`"
        case .strikethrough: return "~~"
        case .highlight: return "=="
        case .link: return "["
        default: return ""
        }
    }
    
    var markdownSuffix: String {
        switch self {
        case .bold: return "**"
        case .italic: return "_"
        case .code: return "`"
        case .strikethrough: return "~~"
        case .highlight: return "=="
        case .link: return "](url)"
        default: return ""
        }
    }
}

// MARK: - Selection Toolbar Window Controller
class SelectionToolbarController: NSObject {
    static let shared = SelectionToolbarController()
    
    private var toolbarWindow: NSWindow?
    private var onAction: ((ToolbarAction, NSRange) -> Void)?
    private var currentSelectionRange: NSRange = NSRange(location: 0, length: 0)
    
    var isVisible: Bool {
        toolbarWindow?.isVisible ?? false
    }
    
    func show(at point: NSPoint, in parentWindow: NSWindow, selectionRange: NSRange, onAction: @escaping (ToolbarAction, NSRange) -> Void) {
        self.onAction = onAction
        self.currentSelectionRange = selectionRange
        
        dismiss()
        
        let toolbarView = NSHostingView(rootView: SelectionToolbarView(onAction: { [weak self] action in
            guard let self = self else { return }
            self.onAction?(action, self.currentSelectionRange)
            self.dismiss()
        }))
        
        let contentSize = toolbarView.fittingSize
        
        // Create toolbar window
        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: contentSize),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        
        window.contentView = toolbarView
        window.backgroundColor = .clear
        window.isOpaque = false
        window.hasShadow = true
        window.level = .floating
        window.isMovableByWindowBackground = false
        
        // Position above selection
        let toolbarX = point.x - contentSize.width / 2
        let toolbarY = point.y + 8
        
        window.setFrameOrigin(NSPoint(x: toolbarX, y: toolbarY))
        
        parentWindow.addChildWindow(window, ordered: .above)
        window.orderFront(nil)
        
        toolbarWindow = window
    }
    
    func dismiss() {
        if let window = toolbarWindow {
            window.parent?.removeChildWindow(window)
            window.orderOut(nil)
            toolbarWindow = nil
        }
    }
}

// MARK: - Selection Toolbar View
struct SelectionToolbarView: View {
    let onAction: (ToolbarAction) -> Void
    
    @State private var hoveredAction: ToolbarAction?
    
    private let mainActions: [ToolbarAction] = [
        .askAI, .heading, .bold, .italic, .code, .strikethrough, .highlight, .link, .alignLeft, .list
    ]
    
    var body: some View {
        HStack(spacing: 4) {
            ForEach(mainActions, id: \.self) { action in
                Button {
                    onAction(action)
                } label: {
                    Group {
                        if action == .askAI {
                            HStack(spacing: 4) {
                                Image(systemName: action.icon)
                                    .font(.system(size: 12, weight: .medium))
                                Text("Ask AI")
                                    .font(.system(size: 12, weight: .medium))
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                        } else if action == .code {
                            // Special style for code - similar to image reference
                            Text("</>")
                                .font(.system(size: 12, weight: .medium, design: .monospaced))
                                .foregroundColor(Color(red: 0.95, green: 0.45, blue: 0.45)) // Reddish/coral color
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .background(
                                    RoundedRectangle(cornerRadius: 6)
                                        .fill(Color(red: 0.15, green: 0.15, blue: 0.17))
                                )
                        } else {
                            Image(systemName: action.icon)
                                .font(.system(size: 14, weight: action == .bold ? .bold : .regular))
                                .padding(.horizontal, 8)
                                .padding(.vertical, 6)
                        }
                    }
                    .background(
                        Group {
                            if action != .code {
                                RoundedRectangle(cornerRadius: 6)
                                    .fill(hoveredAction == action ? Color.white.opacity(0.15) : Color.clear)
                            }
                        }
                    )
                }
                .buttonStyle(.plain)
                .foregroundColor(action == .code ? Color(red: 0.95, green: 0.45, blue: 0.45) : .white.opacity(0.9))
                .onHover { isHovered in
                    hoveredAction = isHovered ? action : nil
                }
                
                // Add divider after Ask AI and after highlight
                if action == .askAI || action == .highlight || action == .link {
                    Divider()
                        .frame(height: 18)
                        .background(Color.white.opacity(0.2))
                }
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color(nsColor: NSColor(red: 0.18, green: 0.18, blue: 0.2, alpha: 0.98)))
                .shadow(color: .black.opacity(0.4), radius: 12, x: 0, y: 4)
        )
    }
}

// MARK: - Preview
#Preview {
    SelectionToolbarView(onAction: { _ in })
        .padding()
        .background(Color.gray)
}
#endif
