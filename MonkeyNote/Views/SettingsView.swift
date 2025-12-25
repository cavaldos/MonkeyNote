//
//  SettingsView.swift
//  Note
//
//  Created by Nguyen Ngoc Khanh on 24/12/25.
//

import SwiftUI

struct SettingsView: View {
    @AppStorage("note.isDarkMode") private var isDarkMode: Bool = true
    @AppStorage("note.fontFamily") private var fontFamily: String = "monospaced"
    @AppStorage("note.fontSize") private var fontSize: Double = 28
    @AppStorage("note.cursorWidth") private var cursorWidth: Double = 2
    @AppStorage("note.cursorBlinkEnabled") private var cursorBlinkEnabled: Bool = true
    @AppStorage("note.cursorAnimationEnabled") private var cursorAnimationEnabled: Bool = true
    @AppStorage("note.cursorAnimationDuration") private var cursorAnimationDuration: Double = 0.15

    @Environment(\.dismiss) private var dismiss
    @ObservedObject var vaultManager: VaultManager

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
            Form {
                Section("Vault") {
                    if let vaultURL = vaultManager.vaultURL {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Current Vault")
                                .font(.headline)
                            Text(vaultURL.path)
                                .font(.system(.caption, design: .monospaced))
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                        }
                        
                        Button("Change Vault") {
                            changeVault()
                        }
                    }
                }

                Section("Theme") {
                    Picker("Appearance", selection: $isDarkMode) {
                        Text("Light").tag(false)
                        Text("Dark").tag(true)
                    }
                    .pickerStyle(.segmented)
                }

                Section("Font") {
                    Picker("Font Family", selection: $fontFamily) {
                        ForEach(defaultFonts, id: \.self) { family in
                            Text(family.capitalized).tag(family)
                        }
                        Divider()
                        ForEach(availableFonts, id: \.self) { family in
                            Text(family).tag(family)
                        }
                    }

                    VStack(alignment: .leading) {
                        Text("Font Size")
                            .font(.headline)
                        HStack {
                            Text("\(Int(fontSize))")
                                .font(.system(.body, design: .monospaced))
                                .frame(width: 40)
                            Slider(value: $fontSize, in: 12...22, step: 2)
                        }
                         Text("Preview")
                             .font(.system(size: fontSize, weight: .regular, design: fontDesign))
                             .foregroundStyle(.secondary)
                             .padding(.top, 4)
                    }
                }

                Section("Cursor") {
                    Toggle("Cursor Blinking", isOn: $cursorBlinkEnabled)
                    Toggle("Cursor Animation", isOn: $cursorAnimationEnabled)

                    if cursorAnimationEnabled {
                        VStack(alignment: .leading) {
                            Text("Animation Duration")
                                .font(.headline)
                            HStack {
                                Text(String(format: "%.2f", cursorAnimationDuration))
                                    .font(.system(.body, design: .monospaced))
                                    .frame(width: 40)
                                Slider(value: $cursorAnimationDuration, in: 0.05...0.5) {
                                    Text("Default (0.15)")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                } minimumValueLabel: {
                                    Text("0.05")
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                } maximumValueLabel: {
                                    Text("0.3")
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }

                    VStack(alignment: .leading) {
                        Text("Cursor Thickness")
                            .font(.headline)
                        HStack {
                            Text("\(Int(cursorWidth))")
                                .font(.system(.body, design: .monospaced))
                                .frame(width: 40)
                            Slider(value: $cursorWidth, in: 2...6, step: 1)
                        }
                    }
                }
            }
            .formStyle(.grouped)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
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
