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
    
    var icon: String {
        switch self {
        case .heading1: return "h1"
        case .heading2: return "h2"
        case .heading3: return "h3"
        case .bulletedList: return "list.bullet"
        case .numberedList: return "list.number"
        case .quote: return "text.quote"
        }
    }
    
    var prefix: String {
        switch self {
        case .heading1: return "# "
        case .heading2: return "## "
        case .heading3: return "### "
        case .bulletedList: return "• "
        case .numberedList: return "1. "
        case .quote: return ">  "
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
        
        // Text
        textField = NSTextField(labelWithString: "")
        textField.font = .systemFont(ofSize: 13)
        textField.textColor = .white
        textField.translatesAutoresizingMaskIntoConstraints = false
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
    
    func configure(with command: SlashCommand, isSelected: Bool) {
        self.command = command
        textField.stringValue = command.rawValue
        
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
    private var selectedIndex: Int = 0
    private var onSelect: ((SlashCommand) -> Void)?
    private var onDismiss: (() -> Void)?
    private var itemViews: [SlashCommandItemView] = []
    
    func show(at point: NSPoint, in parentWindow: NSWindow?, onSelect: @escaping (SlashCommand) -> Void, onDismiss: @escaping () -> Void) {
        self.onSelect = onSelect
        self.onDismiss = onDismiss
        self.selectedIndex = 0
        
        let menuWidth: CGFloat = 200
        let rowHeight: CGFloat = 26
        let verticalPadding: CGFloat = 5
        let itemCount = SlashCommand.allCases.count
        let menuHeight: CGFloat = CGFloat(itemCount) * rowHeight + (verticalPadding * 2)
        
        let panel = NSPanel(
            contentRect: NSRect(x: point.x, y: point.y - menuHeight, width: menuWidth, height: menuHeight),
            styleMask: [.nonactivatingPanel, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.level = .floating
        
        // Background view with dark color
        let backgroundView = NSView(frame: NSRect(x: 0, y: 0, width: menuWidth, height: menuHeight))
        backgroundView.wantsLayer = true
        backgroundView.layer?.cornerRadius = 6
        backgroundView.layer?.masksToBounds = true
        backgroundView.layer?.backgroundColor = NSColor(red: 49/255, green: 49/255, blue: 49/255, alpha: 0.98).cgColor
        backgroundView.layer?.borderWidth = 0.5
        backgroundView.layer?.borderColor = NSColor.white.withAlphaComponent(0.15).cgColor
        
        // Create item views
        itemViews = []
        let commands = SlashCommand.allCases
        for (index, command) in commands.enumerated() {
            let yPosition = menuHeight - verticalPadding - CGFloat(index + 1) * rowHeight
            let itemView = SlashCommandItemView(frame: NSRect(x: 0, y: yPosition, width: menuWidth, height: rowHeight))
            itemView.configure(with: command, isSelected: index == 0)
            itemView.tag = index
            itemView.target = self
            itemView.action = #selector(itemClicked(_:))
            backgroundView.addSubview(itemView)
            itemViews.append(itemView)
        }
        
        panel.contentView = backgroundView
        self.window = panel
        
        parentWindow?.addChildWindow(panel, ordered: .above)
        panel.makeKeyAndOrderFront(nil)
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
        self.itemViews = []
        onDismiss?()
    }
    
    func moveUp() {
        selectedIndex = max(0, selectedIndex - 1)
        updateSelection()
    }
    
    func moveDown() {
        selectedIndex = min(SlashCommand.allCases.count - 1, selectedIndex + 1)
        updateSelection()
    }
    
    func selectCurrent() {
        let command = SlashCommand.allCases[selectedIndex]
        onSelect?(command)
        dismiss()
    }
    
    var isVisible: Bool {
        window != nil
    }
}
#endif
