//
//  MonkeyNoteApp.swift
//  MonkeyNote
//
//  Created by Nguyen Ngoc Khanh on 25/12/25.
//

import SwiftUI

@main
struct MonkeyNoteApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .windowStyle(.hiddenTitleBar)
        .commands {
            CommandGroup(after: .textEditing) {
                Button("Find") {
                    NotificationCenter.default.post(name: .focusSearch, object: nil)
                }
                .keyboardShortcut("f", modifiers: .command)
            }
        }
    }
} 
