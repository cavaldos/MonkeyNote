//
//  SettingsView.swift
//  Note
//
//  Created by Nguyen Ngoc Khanh on 24/12/25.
//

import SwiftUI

enum SettingsTab: String, CaseIterable {
    case appearance = "Appearance"
    case autocomplete = "Autocomplete"
    
    var icon: String {
        switch self {
        case .appearance: return "paintbrush"
        case .autocomplete: return "text.cursor"
        }
    }
}

struct SettingsView: View {
    @AppStorage("note.isDarkMode") private var isDarkMode: Bool = true
    @AppStorage("note.fontFamily") private var fontFamily: String = "monospaced"
    @AppStorage("note.fontSize") private var fontSize: Double = 28
    @AppStorage("note.cursorWidth") private var cursorWidth: Double = 2
    @AppStorage("note.cursorBlinkEnabled") private var cursorBlinkEnabled: Bool = true
    @AppStorage("note.cursorAnimationEnabled") private var cursorAnimationEnabled: Bool = true
    @AppStorage("note.cursorAnimationDuration") private var cursorAnimationDuration: Double = 0.15
    @AppStorage("note.autocompleteEnabled") private var autocompleteEnabled: Bool = true
    @AppStorage("note.autocompleteDelay") private var autocompleteDelay: Double = 0.0
    @AppStorage("note.autocompleteOpacity") private var autocompleteOpacity: Double = 0.5

    @Environment(\.dismiss) private var dismiss
    @ObservedObject var vaultManager: VaultManager
    
    @State private var selectedTab: SettingsTab = .appearance

    private let defaultFonts = ["monospaced", "rounded", "serif"]

    private let availableFonts: [String] = {
        let defaults = ["monospaced", "rounded", "serif"]
        #if os(iOS)
        let systemFonts = UIFont.familyNames.sorted()
        #else
        let systemFonts = NSFontManager.shared.availableFontFamilies.sorted()
        #endif
        return defaults + systemFonts.filter { !defaults.contains($0) }
    }()

    var body: some View {
        NavigationStack {
            HStack(spacing: 0) {
                // Sidebar
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(SettingsTab.allCases, id: \.self) { tab in
                        Button {
                            selectedTab = tab
                        } label: {
                            HStack(spacing: 8) {
                                Image(systemName: tab.icon)
                                    .frame(width: 20)
                                Text(tab.rawValue)
                                Spacer()
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(
                                RoundedRectangle(cornerRadius: 6)
                                    .fill(selectedTab == tab ? Color.accentColor.opacity(0.2) : Color.clear)
                            )
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .foregroundColor(selectedTab == tab ? .accentColor : .primary)
                    }
                    Spacer()
                }
                .padding(.vertical, 12)
                .padding(.horizontal, 8)
                .frame(width: 180)
                .background(Color(nsColor: .controlBackgroundColor).opacity(0.5))
                
                Divider()
                
                // Content
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        switch selectedTab {
                        case .appearance:
                            appearanceContent
                        case .autocomplete:
                            autocompleteContent
                        }
                    }
                    .padding(20)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .frame(minWidth: 500, minHeight: 400)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }
    
    // MARK: - Appearance Tab
    private var appearanceContent: some View {
        VStack(alignment: .leading, spacing: 24) {
            // Vault Section
            settingsSection("Vault") {
                if let vaultURL = vaultManager.vaultURL {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(vaultURL.path)
                            .font(.system(.caption, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                        
                        Button("Change Vault") {
                            changeVault()
                        }
                        .buttonStyle(.bordered)
                    }
                }
            }
            
            // Theme Section
            settingsSection("Theme") {
                Picker("Appearance", selection: $isDarkMode) {
                    Text("Light").tag(false)
                    Text("Dark").tag(true)
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: 200)
            }
            
            // Font Section
            settingsSection("Font") {
                VStack(alignment: .leading, spacing: 16) {
                    Picker("Font Family", selection: $fontFamily) {
                        ForEach(defaultFonts, id: \.self) { family in
                            Text(family.capitalized).tag(family)
                        }
                        Divider()
                        ForEach(availableFonts, id: \.self) { family in
                            Text(family).tag(family)
                        }
                    }
                    .frame(maxWidth: 200)
                    
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Font Size: \(Int(fontSize))")
                            .font(.subheadline)
                        Slider(value: $fontSize, in: 12...22, step: 2)
                            .frame(maxWidth: 250)
                        Text("Preview")
                            .font(.system(size: fontSize, weight: .regular, design: fontDesign))
                            .foregroundStyle(.secondary)
                    }
                }
            }
            
            // Cursor Section
            settingsSection("Cursor") {
                VStack(alignment: .leading, spacing: 12) {
                    Toggle("Cursor Blinking", isOn: $cursorBlinkEnabled)
                    Toggle("Cursor Animation", isOn: $cursorAnimationEnabled)
                    
                    if cursorAnimationEnabled {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Animation Duration: \(String(format: "%.2f", cursorAnimationDuration))s")
                                .font(.subheadline)
                            Slider(value: $cursorAnimationDuration, in: 0.05...0.5)
                                .frame(maxWidth: 250)
                        }
                    }
                    
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Cursor Thickness: \(Int(cursorWidth))")
                            .font(.subheadline)
                        Slider(value: $cursorWidth, in: 2...6, step: 1)
                            .frame(maxWidth: 250)
                    }
                }
            }
            
            Spacer()
        }
    }
    
    // MARK: - Autocomplete Tab
    private var autocompleteContent: some View {
        VStack(alignment: .leading, spacing: 24) {
            settingsSection("Word Suggestions") {
                VStack(alignment: .leading, spacing: 16) {
                    Toggle("Enable Autocomplete", isOn: $autocompleteEnabled)
                    
                    Text("When enabled, word suggestions will appear as ghost text while you type. Press Tab to accept the suggestion.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            
            if autocompleteEnabled {
                settingsSection("Timing") {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Suggestion Delay: \(Int(autocompleteDelay * 1000))ms")
                            .font(.subheadline)
                        Slider(value: $autocompleteDelay, in: 0...1.0, step: 0.05)
                            .frame(maxWidth: 250)
                        Text("How long to wait before showing suggestions")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                
                settingsSection("Appearance") {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Ghost Text Opacity: \(Int(autocompleteOpacity * 100))%")
                            .font(.subheadline)
                        Slider(value: $autocompleteOpacity, in: 0.3...0.9, step: 0.1)
                            .frame(maxWidth: 250)
                        
                        // Preview
                        HStack(spacing: 0) {
                            Text("compl")
                                .font(.system(.body, design: .monospaced))
                            Text("ete")
                                .font(.system(.body, design: .monospaced))
                                .foregroundStyle(.gray.opacity(autocompleteOpacity))
                        }
                        .padding(8)
                        .background(
                            RoundedRectangle(cornerRadius: 6)
                                .fill(Color(nsColor: .textBackgroundColor))
                        )
                    }
                }
                
                settingsSection("Usage") {
                    VStack(alignment: .leading, spacing: 4) {
                        Label("Type at least 2 characters", systemImage: "character.cursor.ibeam")
                        Label("Ghost text appears with suggestion", systemImage: "text.append")
                        Label("Press Tab to accept", systemImage: "arrow.right.to.line")
                        Label("Press Escape to dismiss", systemImage: "escape")
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
            }
            
            Spacer()
        }
    }
    
    // MARK: - Helper Views
    private func settingsSection<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.headline)
                .foregroundStyle(.primary)
            
            content()
        }
    }

    private var fontDesign: Font.Design {
        switch fontFamily {
        case "rounded": return .rounded
        case "serif": return .serif
        default: return .monospaced
        }
    }
    
    private func changeVault() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = true
        panel.title = "Select Vault Folder"
        panel.prompt = "Open"
        panel.message = "Choose a folder to store your markdown notes"
        
        if panel.runModal() == .OK, let url = panel.url {
            vaultManager.setVault(url: url)
        }
    }
}
