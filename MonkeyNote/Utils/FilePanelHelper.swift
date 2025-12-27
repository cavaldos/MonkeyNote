//
//  FilePanelHelper.swift
//  MonkeyNote
//
//  Created by Nguyen Ngoc Khanh on 27/12/25.
//

#if os(macOS)
import AppKit

enum FilePanelHelper {

    static func selectVaultFolder(onSelect: @escaping (URL) -> Void) {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = true
        panel.title = "Select Vault Folder"
        panel.prompt = "Open"
        panel.message = "Choose a folder to store your markdown notes"

        if panel.runModal() == .OK, let url = panel.url {
            onSelect(url)
        }
    }

    static func selectCustomWordFolder(onSelect: @escaping (URL) -> Void) {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = false
        panel.title = "Select Word Dictionary Folder"
        panel.prompt = "Select"
        panel.message = "Choose a folder containing .txt files with words for autocomplete"

        if panel.runModal() == .OK, let url = panel.url {
            onSelect(url)
        }
    }
}
#endif
