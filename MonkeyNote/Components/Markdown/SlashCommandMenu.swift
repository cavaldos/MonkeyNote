//
//  SlashCommandMenu.swift
//  MonkeyNote
//
//  Created by Nguyen Ngoc Khanh on 25/12/25.
//

#if os(macOS)
import SwiftUI
import AppKit

// MARK: - Slash Command Menu
enum SlashCommand: String, CaseIterable {
    case heading1 = "Heading 1"
    case heading2 = "Heading 2"
    case heading3 = "Heading 3"
    case bulletedList = "Bulleted List"
    case numberedList = "Numbered List"
    case quote = "Quote"
    case callout = "Callout"
    case divider = "Divider"
    
    var icon: String {
        switch self {
        case .heading1: return "h1"
        case .heading2: return "h2"
        case .heading3: return "h3"
        case .bulletedList: return "list.bullet"
        case .numberedList: return "list.number"
        case .quote: return "text.quote"
        case .callout: return "bubble.left.fill"
        case .divider: return "minus"
        }
    }
    
    var prefix: String {
        switch self {
        case .heading1: return "# "
        case .heading2: return "## "
        case .heading3: return "### "
        case .bulletedList: return "• "
        case .numberedList: return "1. "
        case .quote: return "> "
        case .callout: return "> [!note]   "
        case .divider: return "---"
        }
    }
    
    // Custom SF Symbol or text for header icons
    var useTextIcon: Bool {
        switch self {
        case .heading1, .heading2, .heading3: return true
        default: return false
        }
    }
}

// Custom clickable item view
class SlashCommandItemView: NSControl {
    private var textField: NSTextField!
    private var iconView: NSImageView!
    private var iconLabel: NSTextField!  // For text-based icons like H1, H2, H3
    private var backgroundLayer: CALayer!
    private var command: SlashCommand?
    private var isItemSelected: Bool = false
    
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setupView()
    }
    
    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupView()
    }
    
    private func setupView() {
        wantsLayer = true
        
        backgroundLayer = CALayer()
        backgroundLayer.cornerRadius = 4
        backgroundLayer.backgroundColor = NSColor.clear.cgColor
        layer?.addSublayer(backgroundLayer)
        
        // Icon (SF Symbol)
        iconView = NSImageView()
        iconView.translatesAutoresizingMaskIntoConstraints = false
        iconView.contentTintColor = .white.withAlphaComponent(0.85)
        addSubview(iconView)
        
        // Icon Label (for text icons like H1, H2, H3)
        iconLabel = NSTextField(labelWithString: "")
        iconLabel.font = .systemFont(ofSize: 11, weight: .bold)
        iconLabel.textColor = .white.withAlphaComponent(0.85)
        iconLabel.translatesAutoresizingMaskIntoConstraints = false
        iconLabel.alignment = .center
        addSubview(iconLabel)
        
        // Text - use attributed string for highlighting
        textField = NSTextField(labelWithString: "")
        textField.font = .systemFont(ofSize: 13)
        textField.textColor = .white
        textField.translatesAutoresizingMaskIntoConstraints = false
        textField.allowsEditingTextAttributes = true
        addSubview(textField)
        
        NSLayoutConstraint.activate([
            iconView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 10),
            iconView.centerYAnchor.constraint(equalTo: centerYAnchor),
            iconView.widthAnchor.constraint(equalToConstant: 16),
            iconView.heightAnchor.constraint(equalToConstant: 16),
            
            iconLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 10),
            iconLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
            iconLabel.widthAnchor.constraint(equalToConstant: 16),
            
            textField.leadingAnchor.constraint(equalTo: iconView.trailingAnchor, constant: 8),
            textField.centerYAnchor.constraint(equalTo: centerYAnchor)
        ])
    }
    
    override func layout() {
        super.layout()
        backgroundLayer.frame = bounds.insetBy(dx: 5, dy: 0)
    }
    
    func configure(with command: SlashCommand, isSelected: Bool, highlightText: String = "") {
        self.command = command
        
        // Create attributed string with highlight
        let commandName = command.rawValue
        let attributedString = NSMutableAttributedString(string: commandName)
        
        // Base attributes
        let baseAttributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 13),
            .foregroundColor: NSColor.white
        ]
        attributedString.addAttributes(baseAttributes, range: NSRange(location: 0, length: commandName.count))
        
        // Highlight matching text (case-insensitive)
        if !highlightText.isEmpty {
            let lowercaseName = commandName.lowercased()
            let lowercaseHighlight = highlightText.lowercased()
            
            if let range = lowercaseName.range(of: lowercaseHighlight) {
                let nsRange = NSRange(range, in: commandName)
                let highlightAttributes: [NSAttributedString.Key: Any] = [
                    .font: NSFont.systemFont(ofSize: 13, weight: .semibold),
                    .foregroundColor: NSColor(red: 255/255, green: 180/255, blue: 100/255, alpha: 1.0) // Orange highlight
                ]
                attributedString.addAttributes(highlightAttributes, range: nsRange)
            }
        }
        
        textField.attributedStringValue = attributedString
        
        if command.useTextIcon {
            // Use text icon (H1, H2, H3)
            iconView.isHidden = true
            iconLabel.isHidden = false
            iconLabel.stringValue = command.icon.uppercased()
        } else {
            // Use SF Symbol
            iconView.isHidden = false
            iconLabel.isHidden = true
            iconView.image = NSImage(systemSymbolName: command.icon, accessibilityDescription: nil)
        }
        
        setSelected(isSelected)
    }
    
    func setSelected(_ selected: Bool) {
        isItemSelected = selected
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        backgroundLayer.backgroundColor = selected ? NSColor.white.withAlphaComponent(0.1).cgColor : NSColor.clear.cgColor
        CATransaction.commit()
    }
    
    override func mouseDown(with event: NSEvent) {
        sendAction(action, to: target)
    }
    
    override func mouseEntered(with event: NSEvent) {
        setSelected(true)
    }
    
    override func mouseExited(with event: NSEvent) {
        // Will be updated by controller
    }
    
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        for trackingArea in trackingAreas {
            removeTrackingArea(trackingArea)
        }
        let trackingArea = NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .activeAlways],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(trackingArea)
    }
}

class SlashCommandWindowController: NSObject {
    private var window: NSWindow?
    private var backgroundView: NSView?
    private var noResultsLabel: NSTextField?
    private var selectedIndex: Int = 0
    private var onSelect: ((SlashCommand) -> Void)?
    private var onDismiss: (() -> Void)?
    private var itemViews: [SlashCommandItemView] = []
    
    // Filter support
    private var filterText: String = ""
    private var filteredCommands: [SlashCommand] = SlashCommand.allCases
    private var menuOriginPoint: NSPoint = .zero
    private weak var parentWindow: NSWindow?
    
    private let menuWidth: CGFloat = 200
    private let rowHeight: CGFloat = 26
    private let verticalPadding: CGFloat = 5
    private let noResultsHeight: CGFloat = 36
    
    func show(at point: NSPoint, in parentWindow: NSWindow?, onSelect: @escaping (SlashCommand) -> Void, onDismiss: @escaping () -> Void) {
        self.onSelect = onSelect
        self.onDismiss = onDismiss
        self.selectedIndex = 0
        self.filterText = ""
        self.filteredCommands = SlashCommand.allCases
        self.menuOriginPoint = point
        self.parentWindow = parentWindow
        
        createWindow()
    }
    
    private func createWindow() {
        // Remove existing window if any
        if let existingWindow = window {
            existingWindow.parent?.removeChildWindow(existingWindow)
            existingWindow.orderOut(nil)
        }
        
        let menuHeight = calculateMenuHeight()
        
        let panel = NSPanel(
            contentRect: NSRect(x: menuOriginPoint.x, y: menuOriginPoint.y - menuHeight, width: menuWidth, height: menuHeight),
            styleMask: [.nonactivatingPanel, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.level = .floating
        
        // Background view with dark color
        let bgView = NSView(frame: NSRect(x: 0, y: 0, width: menuWidth, height: menuHeight))
        bgView.wantsLayer = true
        bgView.layer?.cornerRadius = 6
        bgView.layer?.masksToBounds = true
        bgView.layer?.backgroundColor = NSColor(red: 49/255, green: 49/255, blue: 49/255, alpha: 0.98).cgColor
        bgView.layer?.borderWidth = 0.5
        bgView.layer?.borderColor = NSColor.white.withAlphaComponent(0.15).cgColor
        
        backgroundView = bgView
        
        // Create item views or no results label
        rebuildItemViews()
        
        panel.contentView = bgView
        self.window = panel
        
        parentWindow?.addChildWindow(panel, ordered: .above)
        panel.makeKeyAndOrderFront(nil)
    }
    
    private func calculateMenuHeight() -> CGFloat {
        if filteredCommands.isEmpty {
            return noResultsHeight + (verticalPadding * 2)
        }
        return CGFloat(filteredCommands.count) * rowHeight + (verticalPadding * 2)
    }
    
    private func rebuildItemViews() {
        guard let bgView = backgroundView else { return }
        
        // Remove existing subviews
        bgView.subviews.forEach { $0.removeFromSuperview() }
        itemViews.removeAll()
        noResultsLabel = nil
        
        let menuHeight = calculateMenuHeight()
        
        if filteredCommands.isEmpty {
            // Show "No commands found" label - centered both horizontally and vertically
            let label = NSTextField(labelWithString: "No commands found")
            label.font = .systemFont(ofSize: 13)
            label.textColor = .white.withAlphaComponent(0.5)
            label.alignment = .center
            label.translatesAutoresizingMaskIntoConstraints = false
            bgView.addSubview(label)
            
            NSLayoutConstraint.activate([
                label.centerXAnchor.constraint(equalTo: bgView.centerXAnchor),
                label.centerYAnchor.constraint(equalTo: bgView.centerYAnchor)
            ])
            
            noResultsLabel = label
        } else {
            // Create item views for filtered commands
            for (index, command) in filteredCommands.enumerated() {
                let yPosition = menuHeight - verticalPadding - CGFloat(index + 1) * rowHeight
                let itemView = SlashCommandItemView(frame: NSRect(x: 0, y: yPosition, width: menuWidth, height: rowHeight))
                itemView.configure(with: command, isSelected: index == selectedIndex, highlightText: filterText)
                itemView.tag = index
                itemView.target = self
                itemView.action = #selector(itemClicked(_:))
                bgView.addSubview(itemView)
                itemViews.append(itemView)
            }
        }
    }
    
    func updateFilter(_ text: String) {
        filterText = text
        
        // Filter commands based on text (case-insensitive)
        if text.isEmpty {
            filteredCommands = SlashCommand.allCases
        } else {
            filteredCommands = SlashCommand.allCases.filter { command in
                command.rawValue.lowercased().contains(text.lowercased())
            }
        }
        
        // Reset selection to first item
        selectedIndex = 0
        
        // Rebuild the menu with new filtered results
        updateWindowSize()
        rebuildItemViews()
    }
    
    private func updateWindowSize() {
        guard let window = window, let bgView = backgroundView else { return }
        
        let menuHeight = calculateMenuHeight()
        
        // Update window frame
        var frame = window.frame
        frame.size.height = menuHeight
        frame.origin.y = menuOriginPoint.y - menuHeight
        window.setFrame(frame, display: true, animate: false)
        
        // Update background view frame
        bgView.frame = NSRect(x: 0, y: 0, width: menuWidth, height: menuHeight)
    }
    
    private func updateSelection() {
        for (index, itemView) in itemViews.enumerated() {
            itemView.setSelected(index == selectedIndex)
        }
    }
    
    @objc private func itemClicked(_ sender: SlashCommandItemView) {
        selectedIndex = sender.tag
        selectCurrent()
    }
    
    func dismiss() {
        if let window = self.window {
            window.parent?.removeChildWindow(window)
            window.orderOut(nil)
        }
        self.window = nil
        self.backgroundView = nil
        self.itemViews = []
        self.filterText = ""
        self.filteredCommands = SlashCommand.allCases
        onDismiss?()
    }
    
    func moveUp() {
        guard !filteredCommands.isEmpty else { return }
        selectedIndex = max(0, selectedIndex - 1)
        updateSelection()
    }
    
    func moveDown() {
        guard !filteredCommands.isEmpty else { return }
        selectedIndex = min(filteredCommands.count - 1, selectedIndex + 1)
        updateSelection()
    }
    
    func selectCurrent() {
        guard !filteredCommands.isEmpty, selectedIndex < filteredCommands.count else { return }
        let command = filteredCommands[selectedIndex]
        onSelect?(command)
        dismiss()
    }
    
    var isVisible: Bool {
        window != nil
    }
    
    var currentFilterText: String {
        filterText
    }
    
    var hasResults: Bool {
        !filteredCommands.isEmpty
    }
}
#endif
