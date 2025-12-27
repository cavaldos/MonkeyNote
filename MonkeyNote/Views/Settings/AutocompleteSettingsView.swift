//
//  AutocompleteSettingsView.swift
//  MonkeyNote
//
//  Created by Nguyen Ngoc Khanh on 27/12/25.
//

import SwiftUI

struct AutocompleteSettingsView: View {
    @AppStorage("note.autocompleteEnabled") private var autocompleteEnabled: Bool = true
    @AppStorage("note.autocompleteDelay") private var autocompleteDelay: Double = 0.05
    @AppStorage("note.autocompleteOpacity") private var autocompleteOpacity: Double = 0.5
    @AppStorage("note.useBuiltInDictionary") private var useBuiltInDictionary: Bool = true
    @AppStorage("note.minWordLength") private var minWordLength: Int = 4
    @AppStorage("note.suggestionMode") private var suggestionMode: String = "word"

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            SettingsSection("Autocomplete") {
                VStack(alignment: .leading, spacing: 16) {
                    Toggle("Enable Autocomplete", isOn: $autocompleteEnabled)
                }
            }

            if autocompleteEnabled {
                SettingsSection("Suggestion Mode") {
                    VStack(alignment: .leading, spacing: 12) {
                        Picker("Mode", selection: $suggestionMode) {
                            ForEach(SuggestionMode.allCases, id: \.rawValue) { mode in
                                Label(mode.displayName, systemImage: mode.icon)
                                    .tag(mode.rawValue)
                            }
                        }
                        .pickerStyle(.segmented)
                        .frame(maxWidth: 250)

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

                if suggestionMode == SuggestionMode.word.rawValue {
                    SettingsSection("Word Filter") {
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

                    SettingsSection("Custom Word Dictionary") {
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
                                        FilePanelHelper.selectCustomWordFolder { url in
                                            WordSuggestionManager.shared.setCustomFolder(url)
                                        }
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
                                    FilePanelHelper.selectCustomWordFolder { url in
                                        WordSuggestionManager.shared.setCustomFolder(url)
                                    }
                                }
                                .buttonStyle(.bordered)
                            }

                            Toggle("Use built-in dictionary (\(WordSuggestionManager.shared.bundledWordCount) words)", isOn: $useBuiltInDictionary)
                                .onChange(of: useBuiltInDictionary) { _, newValue in
                                    WordSuggestionManager.shared.setUseBuiltIn(newValue)
                                }
                        }
                    }
                }

                SettingsSection("Timing") {
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

                SettingsSection("Appearance") {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Ghost Text Opacity: \(Int(autocompleteOpacity * 100))%")
                            .font(.subheadline)
                        Slider(value: $autocompleteOpacity, in: 0.3...0.9, step: 0.1)
                            .frame(maxWidth: 250)

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

                SettingsSection("Usage") {
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
}
