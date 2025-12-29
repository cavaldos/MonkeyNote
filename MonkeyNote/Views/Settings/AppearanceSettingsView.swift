//
//  AppearanceSettingsView.swift
//  MonkeyNote
//
//  Created by Nguyen Ngoc Khanh on 27/12/25.
//

import SwiftUI

struct AppearanceSettingsView: View {
    @AppStorage("note.isDarkMode") private var isDarkMode: Bool = true
    @AppStorage("note.fontFamily") private var fontFamily: String = "monospaced"
    @AppStorage("note.fontSize") private var fontSize: Double = 28
    @AppStorage("note.cursorWidth") private var cursorWidth: Double = 2
    @AppStorage("note.cursorBlinkEnabled") private var cursorBlinkEnabled: Bool = true
    @AppStorage("note.cursorAnimationEnabled") private var cursorAnimationEnabled: Bool = true
    @AppStorage("note.cursorAnimationDuration") private var cursorAnimationDuration: Double = 0.15

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
                            .font(.system(size: fontSize, weight: .regular, design: FontHelper.getFontDesign(from: fontFamily)))
                            .foregroundStyle(.secondary)
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

            Spacer()
        }
    }
}
