//
//  SettingsView.swift
//  Note
//
//  Created by Nguyen Ngoc Khanh on 24/12/25.
//

import SwiftUI

enum SuggestionMode: String, CaseIterable {
    case word = "word"
    case sentence = "sentence"
    
    var displayName: String {
        switch self {
        case .word: return "Word"
        case .sentence: return "Sentence"
        }
    }
    
    var icon: String {
        switch self {
        case .word: return "textformat.abc"
        case .sentence: return "text.quote"
        }
    }
}

enum SettingsTab: String, CaseIterable {
    case appearance = "Appearance"
    case autocomplete = "Autocomplete"
    case about = "About"
    
    var icon: String {
        switch self {
        case .appearance: return "paintbrush"
        case .autocomplete: return "text.cursor"
        case .about: return "info.circle"
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
    @AppStorage("note.autocompleteDelay") private var autocompleteDelay: Double = 0.05
    @AppStorage("note.autocompleteOpacity") private var autocompleteOpacity: Double = 0.5
    @AppStorage("note.useBuiltInDictionary") private var useBuiltInDictionary: Bool = true
    @AppStorage("note.minWordLength") private var minWordLength: Int = 4
    @AppStorage("note.suggestionMode") private var suggestionMode: String = "word"

    @Environment(\.dismiss) private var dismiss
    @ObservedObject var vaultManager: VaultManager
    var onVaultChanged: (() -> Void)? = nil
    
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
                        case .about:
                            aboutContent
                        }
                    }
                    .padding(20)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .scrollIndicators(.hidden)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .frame(minWidth: 520, minHeight: 400)
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
            settingsSection("Autocomplete") {
                VStack(alignment: .leading, spacing: 16) {
                    Toggle("Enable Autocomplete", isOn: $autocompleteEnabled)
                }
            }
            
            if autocompleteEnabled {
                settingsSection("Suggestion Mode") {
                    VStack(alignment: .leading, spacing: 12) {
                        Picker("Mode", selection: $suggestionMode) {
                            ForEach(SuggestionMode.allCases, id: \.rawValue) { mode in
                                Label(mode.displayName, systemImage: mode.icon)
                                    .tag(mode.rawValue)
                            }
                        }
                        .pickerStyle(.segmented)
                        .frame(maxWidth: 250)
                        
                        // Warning message for sentence mode
                        if suggestionMode == SuggestionMode.sentence.rawValue {
                            HStack(spacing: 8) {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .foregroundStyle(.orange)
                                Text("This feature is under development")
                                    .font(.subheadline)
                                    .foregroundStyle(.orange)
                            }
                            .padding(12)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(
                                RoundedRectangle(cornerRadius: 8)
                                    .fill(Color.orange.opacity(0.15))
                            )
                        }
                    }
                }
                
                // Only show word-related settings when in word mode
                if suggestionMode == SuggestionMode.word.rawValue {
                    settingsSection("Word Filter") {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Minimum Word Length: \(minWordLength) characters")
                                .font(.subheadline)
                            Slider(value: Binding(
                                get: { Double(minWordLength) },
                                set: { minWordLength = Int($0) }
                            ), in: 2...8, step: 1)
                                .frame(maxWidth: 250)
                            Text("Words shorter than this will not be suggested (e.g., 'a', 'the', 'is')")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .onChange(of: minWordLength) { _, newValue in
                            WordSuggestionManager.shared.setMinWordLength(newValue)
                        }
                    }
                    
                    settingsSection("Custom Word Dictionary") {
                        VStack(alignment: .leading, spacing: 12) {
                        if let folderURL = WordSuggestionManager.shared.getCustomFolderURL() {
                            VStack(alignment: .leading, spacing: 8) {
                                HStack {
                                    Image(systemName: "folder.fill")
                                        .foregroundStyle(.blue)
                                    Text(folderURL.lastPathComponent)
                                        .font(.system(.body, design: .monospaced))
                                }
                                
                                Text(folderURL.path)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(2)
                                
                                HStack {
                                    Text("\(WordSuggestionManager.shared.customWordCount) words loaded")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                    
                                    Spacer()
                                    
                                    Button("Reload") {
                                        WordSuggestionManager.shared.reloadCustomWords()
                                    }
                                    .buttonStyle(.bordered)
                                    .controlSize(.small)
                                }
                            }
                            .padding(12)
                            .background(
                                RoundedRectangle(cornerRadius: 8)
                                    .fill(Color(nsColor: .controlBackgroundColor))
                            )
                            
                            HStack {
                                Button("Change Folder") {
                                    selectCustomWordFolder()
                                }
                                .buttonStyle(.bordered)
                                
                                Button("Remove") {
                                    WordSuggestionManager.shared.setCustomFolder(nil)
                                }
                                .buttonStyle(.bordered)
                                .foregroundColor(.red)
                            }
                        } else {
                            Text("Add a folder containing .txt files to expand your word suggestions.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            
                            Button("Select Folder") {
                                selectCustomWordFolder()
                            }
                            .buttonStyle(.bordered)
                        }
                        
                        Toggle("Use built-in dictionary (\(WordSuggestionManager.shared.bundledWordCount) words)", isOn: $useBuiltInDictionary)
                            .onChange(of: useBuiltInDictionary) { _, newValue in
                                WordSuggestionManager.shared.setUseBuiltIn(newValue)
                            }
                    }
                }
                } // End of word mode settings
                
                settingsSection("Timing") {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Suggestion Delay: \(Int(autocompleteDelay * 1000))ms")
                            .font(.subheadline)
                        Slider(value: $autocompleteDelay, in: 0...0.5, step: 0.05)
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
    
    // MARK: - About Tab
    private var aboutContent: some View {
        VStack(alignment: .leading, spacing: 24) {
            VStack(spacing: 16) {
                Image(nsImage: NSImage(named: "AppIcon") ?? NSImage())
                    .resizable()
                    .frame(width: 96, height: 96)
                    .cornerRadius(16)
                
                VStack(spacing: 4) {
                    Text("MonkeyNote")
                        .font(.system(size: 24, weight: .bold))
                    Text("Version 1.0.0")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(.vertical, 20)
            
            Divider()
            
            VStack(spacing: 12) {
                Button(action: {
                    NSWorkspace.shared.open(URL(string: "https://github.com/cavaldos/MonkeyNote")!)
                }) {
                    Text("Contribute")
                        .frame(maxWidth: .infinity, alignment: .center)
                }
                .buttonStyle(.bordered)
                .frame(width: 150)
                
                Button(action: {
                    NSWorkspace.shared.open(URL(string: "https://github.com/cavaldos/MonkeyNote/issues")!)
                }) {
                    Text("Report a Bug")
                        .frame(maxWidth: .infinity, alignment: .center)
                }
                .buttonStyle(.bordered)
                .frame(width: 150)
                
                Button(action: {
                    NSWorkspace.shared.open(URL(string: "https://ko-fi.com/calvados")!)
                }) {
                    HStack(spacing: 6) {
                        Image(systemName: "heart.fill")
                            .font(.system(size: 12))
                        Text("Support me")
                    }
                    .frame(maxWidth: .infinity, alignment: .center)
                }
                .buttonStyle(.bordered)
                .frame(width: 150)
            }
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(.vertical, 12)
        
            
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
            // Save current vault before changing
            onVaultChanged?()
            
            // Then change vault
            vaultManager.setVault(url: url)
        }
    }
    
    private func selectCustomWordFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = false
        panel.title = "Select Word Dictionary Folder"
        panel.prompt = "Select"
        panel.message = "Choose a folder containing .txt files with words for autocomplete"
        
        if panel.runModal() == .OK, let url = panel.url {
            WordSuggestionManager.shared.setCustomFolder(url)
        }
    }
}
