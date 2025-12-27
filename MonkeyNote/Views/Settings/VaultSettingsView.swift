//
//  VaultSettingsView.swift
//  MonkeyNote
//
//  Created by Nguyen Ngoc Khanh on 27/12/25.
//

import SwiftUI

struct VaultSettingsView: View {
    @ObservedObject var vaultManager: VaultManager
    var onVaultChanged: (() -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            SettingsSection("Current Vault") {
                if let vaultURL = vaultManager.vaultURL {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(vaultURL.path)
                            .font(.system(.caption, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .lineLimit(2)

                        Button("Change Vault") {
                            FilePanelHelper.selectVaultFolder { url in
                                onVaultChanged?()
                                vaultManager.setVault(url: url)
                            }
                        }
                        .buttonStyle(.bordered)
                    }
                }
            }

            SettingsSection("Recent Vaults") {
                if vaultManager.recentVaults.isEmpty {
                    Text("No recent vaults")
                        .foregroundStyle(.secondary)
                        .font(.caption)
                } else {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(vaultManager.recentVaults) { vault in
                            HStack(spacing: 8) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(vault.folderName)
                                        .font(.system(.body, design: .monospaced))
                                    Text(vault.path)
                                        .font(.system(.caption, design: .monospaced))
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                    Text("Last accessed: \(DateFormatter.formatDate(vault.lastAccessed))")
                                        .font(.system(.caption2, design: .monospaced))
                                        .foregroundStyle(.tertiary)
                                }

                                Spacer()

                                Button {
                                    vaultManager.removeFromRecentVaults(id: vault.id)
                                } label: {
                                    Image(systemName: "xmark.circle.fill")
                                        .foregroundStyle(.secondary)
                                }
                                .buttonStyle(.plain)
                                .help("Remove from recent vaults")
                            }
                            .padding(8)
                            .background(
                                RoundedRectangle(cornerRadius: 6)
                                    .fill(Color(nsColor: .controlBackgroundColor))
                            )
                            .contentShape(Rectangle())
                            .onTapGesture {
                                let url = URL(fileURLWithPath: vault.path)
                                onVaultChanged?()
                                vaultManager.setVault(url: url)
                            }
                            .contextMenu {
                                Button {
                                    let url = URL(fileURLWithPath: vault.path)
                                    onVaultChanged?()
                                    vaultManager.setVault(url: url)
                                } label: {
                                    Label("Open Vault", systemImage: "folder")
                                }

                                Divider()

                                Button(role: .destructive) {
                                    vaultManager.removeFromRecentVaults(id: vault.id)
                                } label: {
                                    Label("Remove from List", systemImage: "trash")
                                }
                            }
                        }
                        Spacer()

                        Button(role: .destructive) {
                            vaultManager.clearRecentVaults()
                        } label: {
                            Label("Clear Recent Vaults", systemImage: "trash")
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }
                }
            }

            Spacer()
        }
    }
}
