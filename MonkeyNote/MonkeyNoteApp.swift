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
    private var backingView: NSView?
    
    @Published var isVibrancyEnabled: Bool = UserDefaults.standard.object(forKey: "note.vibrancyEnabled") as? Bool ?? true
    @Published var materialType: String = UserDefaults.standard.string(forKey: "note.vibrancyMaterial") ?? "hudWindow"
    @Published var isWindowPinned: Bool = UserDefaults.standard.object(forKey: "note.windowAlwaysOnTop") as? Bool ?? false
    
    init() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(vibrancySettingDidChange),
            name: .vibrancySettingChanged,
            object: nil
        )

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(windowPinSettingDidChange),
            name: .windowPinSettingChanged,
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

    @objc private func windowPinSettingDidChange() {
        isWindowPinned = UserDefaults.standard.object(forKey: "note.windowAlwaysOnTop") as? Bool ?? false

        if let window = window {
            applyWindowLevel(on: window)
        }
    }
    
    func configureWindow(_ window: NSWindow) {
        self.window = window
        applyWindowLevel(on: window)
        
        if isVibrancyEnabled {
            enableVibrancy(on: window)
        } else {
            disableVibrancy(on: window)
        }
    }

    private func applyWindowLevel(on window: NSWindow) {
        window.level = isWindowPinned ? .floating : .normal
    }
    
    private func enableVibrancy(on window: NSWindow) {
        window.isOpaque = false
        window.backgroundColor = .clear
        
        let material = getMaterial(from: materialType)
        
        if let existingView = visualEffectView {
            existingView.material = material
        } else {
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

        // macOS 27 (Liquid Glass): khe divider của NavigationSplitView không
        // vẽ gì → lộ desktop sắc nét xuyên qua. Lót 1 lớp nền đục cùng tông
        // app NGAY DƯỚI lớp blur để bịt mọi khe trong suốt; lớp blur và các
        // column vẫn vẽ đè lên trên nên hiệu ứng kính mờ giữ nguyên.
        if backingView == nil, let contentView = window.contentView, let blurView = visualEffectView {
            let backing = NSView()
            backing.wantsLayer = true
            backing.translatesAutoresizingMaskIntoConstraints = false
            contentView.addSubview(backing, positioned: .below, relativeTo: blurView)
            NSLayoutConstraint.activate([
                backing.topAnchor.constraint(equalTo: contentView.topAnchor),
                backing.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
                backing.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
                backing.bottomAnchor.constraint(equalTo: contentView.bottomAnchor)
            ])
            backingView = backing
        }
        backingView?.layer?.backgroundColor = opaqueBackingColor().cgColor
    }
    
    private func disableVibrancy(on window: NSWindow) {
        visualEffectView?.removeFromSuperview()
        visualEffectView = nil
        backingView?.removeFromSuperview()
        backingView = nil
        
        window.isOpaque = true
        window.backgroundColor = NSColor.windowBackgroundColor
    }

    // Cùng tông nền đục app dùng khi tắt vibrancy — khe divider bịt lại nhìn
    // như 1 hairline nền app, không lộ desktop.
    private func opaqueBackingColor() -> NSColor {
        let dark = UserDefaults.standard.object(forKey: "note.isDarkMode") as? Bool ?? true
        return dark
            ? NSColor(red: 49.0 / 255.0, green: 49.0 / 255.0, blue: 49.0 / 255.0, alpha: 1.0)
            : NSColor(white: 0.97, alpha: 1.0)
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
