//
//  SettingsView.swift
//  MonkeyNote
//
//  Created by Nguyen Ngoc Khanh on 24/12/25.
//

import SwiftUI

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var vaultManager: VaultManager
    var onVaultChanged: (() -> Void)? = nil

    @State private var selectedTab: SettingsTab = .vault

    var body: some View {
        NavigationStack {
            HStack(spacing: 0) {
                SettingsSidebar(selectedTab: $selectedTab)

                Divider()

                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        switch selectedTab {
                        case .vault:
                            VaultSettingsView(vaultManager: vaultManager, onVaultChanged: onVaultChanged)
                        case .appearance:
                            AppearanceSettingsView()
                        case .autocomplete:
                            AutocompleteSettingsView()
                        case .keyboard:
                            KeyboardSettingsView()
                        case .about:
                            AboutSettingsView()
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
        .onAppear {
            if let savedTab = UserDefaults.standard.string(forKey: "selectedSettingsTab"),
               let tab = SettingsTab(rawValue: savedTab) {
                selectedTab = tab
            }
        }
        .onChange(of: selectedTab) { newValue in
            UserDefaults.standard.set(newValue.rawValue, forKey: "selectedSettingsTab")
        }
    }
}
