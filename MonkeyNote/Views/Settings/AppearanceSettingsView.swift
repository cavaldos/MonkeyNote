//
//  AppearanceSettingsView.swift
//  MonkeyNote
//
//  Created by Nguyen Ngoc Khanh on 27/12/25.
//

import SwiftUI

// MARK: - Vibrancy Material Type
enum VibrancyMaterialType: String, CaseIterable {
    case hudWindow = "hudWindow"
    case popover = "popover"
    case sidebar = "sidebar"
    case underWindowBackground = "underWindowBackground"
    case headerView = "headerView"
    case sheet = "sheet"
    case windowBackground = "windowBackground"
    case menu = "menu"
    case contentBackground = "contentBackground"
    case titlebar = "titlebar"
    
    var displayName: String {
        switch self {
        case .hudWindow: return "HUD Window"
        case .popover: return "Popover"
        case .sidebar: return "Sidebar"
        case .underWindowBackground: return "Under Window"
        case .headerView: return "Header View"
        case .sheet: return "Sheet"
        case .windowBackground: return "Window Background"
        case .menu: return "Menu"
        case .contentBackground: return "Content"
        case .titlebar: return "Titlebar"
        }
    }
    
    #if os(macOS)
    var material: NSVisualEffectView.Material {
        switch self {
        case .hudWindow: return .hudWindow
        case .popover: return .popover
        case .sidebar: return .sidebar
        case .underWindowBackground: return .underWindowBackground
        case .headerView: return .headerView
        case .sheet: return .sheet
        case .windowBackground: return .windowBackground
        case .menu: return .menu
        case .contentBackground: return .contentBackground
        case .titlebar: return .titlebar
        }
    }
    #endif
}

struct AppearanceSettingsView: View {
    @State private var showFontPreviewer: Bool = false
    @AppStorage("note.isDarkMode") private var isDarkMode: Bool = true
    @AppStorage("note.fontFamily") private var fontFamily: String = "monospaced"
    @AppStorage("note.fontSize") private var fontSize: Double = 28
    @AppStorage("note.cursorWidth") private var cursorWidth: Double = 2
    @AppStorage("note.cursorBlinkEnabled") private var cursorBlinkEnabled: Bool = true
    @AppStorage("note.cursorAnimationEnabled") private var cursorAnimationEnabled: Bool = true
    @AppStorage("note.cursorAnimationDuration") private var cursorAnimationDuration: Double = 0.15
    @AppStorage("note.vibrancyEnabled") private var vibrancyEnabled: Bool = true
    @AppStorage("note.vibrancyMaterial") private var vibrancyMaterial: String = "hudWindow"

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

    @State private var recentFonts: [String] = []

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            SettingsSection("Theme") {
                Picker("Appearance", selection: $isDarkMode) {
                    Text("Light").tag(false)
                    Text("Dark").tag(true)
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: 200)
            }

            SettingsSection("Font") {
                VStack(alignment: .leading, spacing: 16) {
                    Picker("Font Family", selection: $fontFamily) {
                        if !recentFonts.isEmpty {
                            Section("Recent Fonts") {
                                ForEach(recentFonts, id: \.self) { family in
                                    Text(family.capitalized).tag(family)
                                }
                            }
                        }
                        
                        Section("Default") {
                            ForEach(defaultFonts, id: \.self) { family in
                                Text(family.capitalized).tag(family)
                            }
                        }
                        
                        Section("All Fonts") {
                            ForEach(availableFonts, id: \.self) { family in
                                Text(family).tag(family)
                            }
                        }
                    }
                    .frame(maxWidth: 200)
                    .onChange(of: fontFamily) { newValue in
                        addToRecentFonts(newValue)
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        Text("Font Size: \(Int(fontSize))")
                            .font(.subheadline)
                        Slider(value: $fontSize, in: 12...22, step: 2)
                            .frame(maxWidth: 250)
                        Text("Preview")
                            .font(.system(size: fontSize, weight: .regular, design: FontHelper.getFontDesign(from: fontFamily)))
                            .foregroundStyle(.secondary)
                        
                        Button("Preview All Fonts") {
                            showFontPreviewer = true
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }
                }
            }

            SettingsSection("Cursor") {
                VStack(alignment: .leading, spacing: 12) {
                    Toggle("Cursor Blinking", isOn: $cursorBlinkEnabled)
                    Toggle("Cursor Animation", isOn: $cursorAnimationEnabled)

                    if cursorAnimationEnabled {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Animation Duration: \(String(format: "%.2f", cursorAnimationDuration))s")
                                .font(.subheadline)
                            Slider(value: $cursorAnimationDuration, in: 0.05...0.3)
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
            
            #if os(macOS)
            SettingsSection("Background Vibrancy") {
                VStack(alignment: .leading, spacing: 12) {
                    Toggle("Enable Vibrancy Effect", isOn: $vibrancyEnabled)
                        .onChange(of: vibrancyEnabled) { _, _ in
                            NotificationCenter.default.post(name: .vibrancySettingChanged, object: nil)
                        }
                    
                    if vibrancyEnabled {
                        Picker("Blur Style", selection: $vibrancyMaterial) {
                            ForEach(VibrancyMaterialType.allCases, id: \.rawValue) { type in
                                Text(type.displayName).tag(type.rawValue)
                            }
                        }
                        .frame(maxWidth: 200)
                        .onChange(of: vibrancyMaterial) { _, _ in
                            NotificationCenter.default.post(name: .vibrancySettingChanged, object: nil)
                        }
                        
                        Text("Vibrancy creates a frosted glass effect, allowing the desktop wallpaper to show through the window.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            #endif

            Spacer()
        }
        .onAppear {
            loadRecentFonts()
        }
        .sheet(isPresented: $showFontPreviewer) {
            FontPreviewerView()
        }
    }

    private func addToRecentFonts(_ font: String) {
        var fonts = loadRecentFontsArray()
        fonts.removeAll { $0 == font }
        fonts.insert(font, at: 0)
        fonts = Array(fonts.prefix(10))
        UserDefaults.standard.set(fonts, forKey: "recentFonts")
        recentFonts = fonts
    }

    private func loadRecentFonts() {
        recentFonts = loadRecentFontsArray()
    }

    private func loadRecentFontsArray() -> [String] {
        UserDefaults.standard.stringArray(forKey: "recentFonts") ?? []
    }
}
