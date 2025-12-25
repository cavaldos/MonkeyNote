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
    case bulletedList = "Bulleted List"
    case numberedList = "Numbered List"
    
    var icon: String {
        switch self {
        case .bulletedList: return "list.bullet"
        case .numberedList: return "list.number"
        }
    }
    
    var prefix: String {
        switch self {
        case .bulletedList: return "• "
        case .numberedList: return "1. "
        }
    }
}

class SlashCommandWindowController: NSObject {
    private var window: NSWindow?
    private var tableView: NSTableView?
    private var selectedIndex: Int = 0
    private var onSelect: ((SlashCommand) -> Void)?
    private var onDismiss: (() -> Void)?
    
    func show(at point: NSPoint, in parentWindow: NSWindow?, onSelect: @escaping (SlashCommand) -> Void, onDismiss: @escaping () -> Void) {
        self.onSelect = onSelect
        self.onDismiss = onDismiss
        self.selectedIndex = 0
        
        let horizontalPadding: CGFloat = 12
        let verticalPadding: CGFloat = 8
        let menuWidth: CGFloat = 220
        let rowHeight: CGFloat = 36
        let menuHeight: CGFloat = CGFloat(SlashCommand.allCases.count) * rowHeight + (verticalPadding * 2)
        
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
        
        let visualEffect = NSVisualEffectView(frame: NSRect(x: 0, y: 0, width: menuWidth, height: menuHeight))
        visualEffect.material = .menu
        visualEffect.state = .active
        visualEffect.wantsLayer = true
        visualEffect.layer?.cornerRadius = 7
        visualEffect.layer?.masksToBounds = true
        
        let scrollView = NSScrollView(frame: NSRect(x: horizontalPadding, y: verticalPadding, width: menuWidth - (horizontalPadding * 2), height: menuHeight - (verticalPadding * 2)))
        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = false
        scrollView.hasHorizontalScroller = false
        
        let tableView = NSTableView(frame: scrollView.bounds)
        tableView.backgroundColor = .clear
        tableView.headerView = nil
        tableView.rowHeight = rowHeight
        tableView.selectionHighlightStyle = .regular
        tableView.intercellSpacing = NSSize(width: 0, height: 4)
        tableView.delegate = self
        tableView.dataSource = self
        tableView.target = self
        tableView.doubleAction = #selector(handleDoubleClick)
        
        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("command"))
        column.width = menuWidth - (horizontalPadding * 2)
        tableView.addTableColumn(column)
        
        scrollView.documentView = tableView
        visualEffect.addSubview(scrollView)
        panel.contentView = visualEffect
        
        self.window = panel
        self.tableView = tableView
        
        parentWindow?.addChildWindow(panel, ordered: .above)
        panel.makeKeyAndOrderFront(nil)
        
        tableView.reloadData()
        tableView.selectRowIndexes(IndexSet(integer: 0), byExtendingSelection: false)
    }
    
    func dismiss() {
        if let window = self.window {
            window.parent?.removeChildWindow(window)
            window.orderOut(nil)
        }
        self.window = nil
        self.tableView = nil
        onDismiss?()
    }
    
    func moveUp() {
        guard let tableView = tableView else { return }
        selectedIndex = max(0, selectedIndex - 1)
        tableView.selectRowIndexes(IndexSet(integer: selectedIndex), byExtendingSelection: false)
        tableView.scrollRowToVisible(selectedIndex)
    }
    
    func moveDown() {
        guard let tableView = tableView else { return }
        selectedIndex = min(SlashCommand.allCases.count - 1, selectedIndex + 1)
        tableView.selectRowIndexes(IndexSet(integer: selectedIndex), byExtendingSelection: false)
        tableView.scrollRowToVisible(selectedIndex)
    }
    
    func selectCurrent() {
        let command = SlashCommand.allCases[selectedIndex]
        onSelect?(command)
        dismiss()
    }
    
    @objc private func handleDoubleClick() {
        guard let tableView = tableView, tableView.clickedRow >= 0 else { return }
        selectedIndex = tableView.clickedRow
        selectCurrent()
    }
    
    var isVisible: Bool {
        window != nil
    }
}

extension SlashCommandWindowController: NSTableViewDataSource, NSTableViewDelegate {
    func numberOfRows(in tableView: NSTableView) -> Int {
        SlashCommand.allCases.count
    }
    
    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let command = SlashCommand.allCases[row]
        
        let cellView = NSTableCellView()
        cellView.wantsLayer = true
        
        let imageView = NSImageView(frame: NSRect(x: 8, y: 8, width: 20, height: 20))
        imageView.image = NSImage(systemSymbolName: command.icon, accessibilityDescription: nil)
        imageView.contentTintColor = .labelColor
        
        let textField = NSTextField(labelWithString: command.rawValue)
        textField.frame = NSRect(x: 36, y: 8, width: 150, height: 20)
        textField.font = .systemFont(ofSize: 13)
        textField.textColor = .labelColor
        
        cellView.addSubview(imageView)
        cellView.addSubview(textField)
        
        return cellView
    }
    
    func tableView(_ tableView: NSTableView, shouldSelectRow row: Int) -> Bool {
        true
    }
    
    func tableViewSelectionDidChange(_ notification: Notification) {
        guard let tableView = notification.object as? NSTableView else { return }
        selectedIndex = tableView.selectedRow
    }
}
#endif
