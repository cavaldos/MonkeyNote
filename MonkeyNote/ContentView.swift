//
//  ContentView.swift
//  MonkeyNote
//
//  Created by Nguyen Ngoc Khanh on 24/12/25.
//  Refactored on 03/01/26.
//

import SwiftUI
#if os(macOS)
import AppKit
#endif

// MARK: - Main View

struct ContentView: View {
    @State private var viewModel = ContentViewModel()
    
    var body: some View {
        NavigationSplitView {
            SidebarView()
        } content: {
            NotesListView()
        } detail: {
            DetailEditorView()
        }
        #if os(macOS)
        .background(SplitDividerSeal())
        #endif
        .environment(viewModel)
        .task {
            viewModel.vaultManager.createVaultIfNeeded()
            viewModel.loadFromVault()
            viewModel.ensureInitialSelection()
            viewModel.refreshTrash()
            viewModel.startWatchingVault()
            viewModel.startWatchingCurrentFile()
        }
        .sheet(item: $viewModel.renameRequest) { request in
            RenameSheet(
                title: request.title,
                placeholder: request.placeholder,
                initialText: request.initialText,
                onCancel: { viewModel.renameRequest = nil },
                onSave: { newName in
                    viewModel.applyRename(request: request, newName: newName)
                    viewModel.renameRequest = nil
                }
            )
        }
        .sheet(isPresented: $viewModel.showSettings) {
            SettingsView(
                vaultManager: viewModel.vaultManager,
                onVaultChanged: {
                    print("💾 Saving current vault before change...")
                    viewModel.isChangingVault = true
                    viewModel.saveAllToDisk()
                }
            )
            .presentationDetents([.medium])
            .presentationDragIndicator(.visible)
        }
        .preferredColorScheme(viewModel.isDarkMode ? .dark : .light)
        .onChange(of: viewModel.vaultManager.vaultURL) { _, newURL in
            print("🔄 Vault changed, resetting folders...")
            viewModel.isChangingVault = false
            viewModel.folders = []
            viewModel.selectedFolderID = nil
            viewModel.selectedNoteID = nil
            viewModel.searchText = ""
            viewModel.trashItems = []
            
            viewModel.loadFromVault()
            viewModel.ensureInitialSelection()
            viewModel.refreshTrash()
            viewModel.startWatchingVault()
            viewModel.startWatchingCurrentFile()
            
            print("📂 Switched to vault: \(newURL?.path ?? "none")")
        }
        .onChange(of: viewModel.selectedNoteID) { _, _ in
            viewModel.startWatchingCurrentFile()
        }
        .onChange(of: viewModel.externalFileURL) { _, _ in
            viewModel.startWatchingCurrentFile()
        }
        .onDisappear {
            viewModel.stopWatching()
            guard !viewModel.isChangingVault else {
                print("⏭️ Skipping save - vault is changing")
                return
            }
            viewModel.saveAllToDisk()
        }
    }
}

// MARK: - Preview

#Preview {
    ContentView()
}

#if os(macOS)
// Sợi hairline đè lên divider — trong suốt với chuột để vẫn kéo resize được.
final class DividerHairlineView: NSView {
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}

// macOS 27 đổi divider list ↔ editor của NavigationSplitView sang kiểu
// paneSplitter rộng 5pt + vẽ trong suốt → thành vệt hở (đo thực tế:
// NSSplitDividerView rộng 5pt; ép dividerStyle=.thin bị SwiftUI giật lại
// ngay trong layout nên không giữ được). Cách này gắn 1 sợi hairline đục
// 1px làm CON của chính divider view → tự bám theo mọi resize/kéo cột.
// (Lớp lót đục ở window lo bịt xuyên thấu xung quanh.)
struct SplitDividerSeal: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let v = NSView(frame: .zero)
        context.coordinator.view = v
        NotificationCenter.default.addObserver(
            context.coordinator,
            selector: #selector(Coordinator.apply),
            name: .vibrancySettingChanged,
            object: nil
        )
        context.coordinator.apply()
        return v
    }
    func updateNSView(_ nsView: NSView, context: Context) {
        context.coordinator.apply()
    }
    func makeCoordinator() -> Coordinator { Coordinator() }

    class Coordinator: NSObject {
        weak var view: NSView?
        private var attempts = 0

        deinit {
            NotificationCenter.default.removeObserver(self)
        }

        @objc func apply() {
            attempts = 0
            reapply()
        }

        func reapply() {
            attempts += 1
            guard let v = view else { return }
            if let root = v.window?.contentView {
                var sealed = false
                for sv in allSplitViews(in: root) where sv.isVertical {
                    for sub in sv.subviews where String(describing: type(of: sub)).contains("Divider") {
                        // Chỉ bịt divider mập (>= 2pt, kiểu paneSplitter của macOS 27);
                        // divider nào đã hairline sẵn thì để yên.
                        guard sub.frame.width >= 2, sub.frame.height > 100 else { continue }
                        if let existing = sub.subviews.first(where: { $0 is DividerHairlineView }) {
                            existing.layer?.backgroundColor = hairlineColor().cgColor
                        } else {
                            let strip = DividerHairlineView()
                            strip.wantsLayer = true
                            strip.layer?.backgroundColor = hairlineColor().cgColor
                            strip.translatesAutoresizingMaskIntoConstraints = false
                            sub.addSubview(strip)
                            NSLayoutConstraint.activate([
                                strip.widthAnchor.constraint(equalToConstant: 1),
                                strip.centerXAnchor.constraint(equalTo: sub.centerXAnchor),
                                strip.topAnchor.constraint(equalTo: sub.topAnchor),
                                strip.bottomAnchor.constraint(equalTo: sub.bottomAnchor)
                            ])
                        }
                        sealed = true
                    }
                }
                if sealed { return }
            }
            if attempts < 80 {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [weak self] in
                    self?.reapply()
                }
            }
        }

        private func hairlineColor() -> NSColor {
            let dark = UserDefaults.standard.object(forKey: "note.isDarkMode") as? Bool ?? true
            return dark ? NSColor(white: 0.30, alpha: 1.0) : NSColor(white: 0.80, alpha: 1.0)
        }

        private func allSplitViews(in v: NSView) -> [NSSplitView] {
            var out: [NSSplitView] = []
            for sub in v.subviews {
                if let sv = sub as? NSSplitView { out.append(sv) }
                out += allSplitViews(in: sub)
            }
            return out
        }
    }
}
#endif
