//
//  KeyboardSettingsView.swift
//  MonkeyNote
//
//  Created by Nguyen Ngoc Khanh on 29/12/25.
//

import SwiftUI

struct KeyboardSettingsView: View {
    @AppStorage("note.doubleTapNavigationEnabled") private var doubleTapNavigationEnabled: Bool = true
    @AppStorage("note.doubleTapDelay") private var doubleTapDelay: Double = 200

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            SettingsSection("Double-tap Navigation") {
                VStack(alignment: .leading, spacing: 16) {
                    Toggle("Enable Double-tap Navigation", isOn: $doubleTapNavigationEnabled)
                    
                    Text("Quickly press a key twice to perform word-level actions instead of character-level.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            if doubleTapNavigationEnabled {
                SettingsSection("Timing") {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Double-tap Delay: \(Int(doubleTapDelay))ms")
                            .font(.subheadline)
                        Slider(value: $doubleTapDelay, in: 100...400, step: 25)
                            .frame(maxWidth: 250)
                        Text("Maximum time between key presses to trigger double-tap action")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                SettingsSection("Supported Keys") {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 12) {
                            KeyBadge(key: "⌫", description: "Delete")
                            Text("Double-tap to delete entire word")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        
                        HStack(spacing: 12) {
                            KeyBadge(key: "←", description: "Left Arrow")
                            Text("Double-tap to move to previous word")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        
                        HStack(spacing: 12) {
                            KeyBadge(key: "→", description: "Right Arrow")
                            Text("Double-tap to move to next word")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                SettingsSection("Tips") {
                    VStack(alignment: .leading, spacing: 4) {
                        Label("Same as Option + Key on Mac", systemImage: "option")
                        Label("Works like word-level navigation", systemImage: "text.word.spacing")
                        Label("Adjust delay if double-tap feels too fast or slow", systemImage: "slider.horizontal.3")
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
            }

            Spacer()
        }
    }
}

// MARK: - Key Badge Component
struct KeyBadge: View {
    let key: String
    let description: String
    
    var body: some View {
        Text(key)
            .font(.system(size: 14, weight: .medium, design: .monospaced))
            .frame(width: 28, height: 28)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color(nsColor: .controlBackgroundColor))
                    .shadow(color: .black.opacity(0.1), radius: 1, x: 0, y: 1)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(Color(nsColor: .separatorColor), lineWidth: 1)
            )
            .help(description)
    }
}
