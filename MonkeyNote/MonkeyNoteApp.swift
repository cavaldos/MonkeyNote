//
//  MonkeyNoteApp.swift
//  MonkeyNote
//
//  Created by Nguyen Ngoc Khanh on 25/12/25.
//

import SwiftUI
import Combine
#if os(macOS)
import AppKit
#endif

@main
struct MonkeyNoteApp: App {
    #if os(macOS)
    @StateObject private var vibrancyConfigurator = VibrancyWindowConfigurator()
    #endif
    
    var body: some Scene {
        WindowGroup {
            ContentView()
                #if os(macOS)
                .withVibrancyEffect(configurator: vibrancyConfigurator)
                #endif
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

// MARK: - Vibrancy Support for macOS
#if os(macOS)

// MARK: - Window Accessor View
struct WindowAccessor: NSViewRepresentable {
    var callback: (NSWindow?) -> Void
    
    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async {
            self.callback(view.window)
        }
        return view
    }
    
    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async {
            self.callback(nsView.window)
        }
    }
}

// MARK: - Vibrancy Window Configurator
class VibrancyWindowConfigurator: ObservableObject {
    private weak var window: NSWindow?
    private var visualEffectView: NSVisualEffectView?
    
    @Published var isVibrancyEnabled: Bool = UserDefaults.standard.object(forKey: "note.vibrancyEnabled") as? Bool ?? true
    @Published var materialType: String = UserDefaults.standard.string(forKey: "note.vibrancyMaterial") ?? "hudWindow"
    
    init() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(vibrancySettingDidChange),
            name: .vibrancySettingChanged,
            object: nil
        )
    }
    
    deinit {
        NotificationCenter.default.removeObserver(self)
    }
    
    @objc private func vibrancySettingDidChange() {
        isVibrancyEnabled = UserDefaults.standard.object(forKey: "note.vibrancyEnabled") as? Bool ?? true
        materialType = UserDefaults.standard.string(forKey: "note.vibrancyMaterial") ?? "hudWindow"
        
        if let window = window {
            configureWindow(window)
        }
    }
    
    func configureWindow(_ window: NSWindow) {
        self.window = window
        
        if isVibrancyEnabled {
            enableVibrancy(on: window)
        } else {
            disableVibrancy(on: window)
        }
    }
    
    private func enableVibrancy(on window: NSWindow) {
        window.isOpaque = false
        window.backgroundColor = .clear
        
        let material = getMaterial(from: materialType)
        
        if let existingView = visualEffectView {
            existingView.material = material
            return
        }
        
        guard let contentView = window.contentView else { return }
        
        let blurView = NSVisualEffectView()
        blurView.material = material
        blurView.blendingMode = .behindWindow
        blurView.state = .active
        blurView.translatesAutoresizingMaskIntoConstraints = false
        
        contentView.addSubview(blurView, positioned: .below, relativeTo: contentView.subviews.first)
        
        NSLayoutConstraint.activate([
            blurView.topAnchor.constraint(equalTo: contentView.topAnchor),
            blurView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            blurView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            blurView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor)
        ])
        
        visualEffectView = blurView
    }
    
    private func disableVibrancy(on window: NSWindow) {
        visualEffectView?.removeFromSuperview()
        visualEffectView = nil
        
        window.isOpaque = true
        window.backgroundColor = NSColor.windowBackgroundColor
    }
    
    private func getMaterial(from string: String) -> NSVisualEffectView.Material {
        switch string {
        case "hudWindow": return .hudWindow
        case "popover": return .popover
        case "sidebar": return .sidebar
        case "underWindowBackground": return .underWindowBackground
        case "headerView": return .headerView
        case "sheet": return .sheet
        case "windowBackground": return .windowBackground
        case "menu": return .menu
        case "contentBackground": return .contentBackground
        case "titlebar": return .titlebar
        default: return .hudWindow
        }
    }
}

// MARK: - View Extension for Vibrancy
extension View {
    func withVibrancyEffect(configurator: VibrancyWindowConfigurator) -> some View {
        self.background(
            WindowAccessor { window in
                if let window = window {
                    configurator.configureWindow(window)
                }
            }
        )
    }
}
#endif 
