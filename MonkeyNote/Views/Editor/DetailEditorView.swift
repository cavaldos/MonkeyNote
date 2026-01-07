//
//  DetailEditorView.swift
//  MonkeyNote
//
//  Created by Assistant on 03/01/26.
//

import SwiftUI
import UniformTypeIdentifiers

struct DetailEditorView: View {
    @Environment(ContentViewModel.self) var viewModel
    
    var body: some View {
        @Bindable var vm = viewModel
        
        ZStack {
            background
            (viewModel.isDarkMode ? Color.black.opacity(0.16) : Color.black.opacity(0.04))
                .ignoresSafeArea()
            
            // Show editor if we have a selected note OR an external file
            if viewModel.selectedNoteIndex == nil && !viewModel.isEditingExternalFile {
                emptyState
            } else {
                editorContent
            }
            
            // Drop overlay
            if viewModel.isDropTargeted {
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color.blue, style: StrokeStyle(lineWidth: 3, dash: [10, 5]))
                    .background(Color.blue.opacity(0.1))
                    .padding(8)
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: viewModel.isDropTargeted)
        .onDrop(of: [.fileURL], isTargeted: $vm.isDropTargeted) { providers in
            viewModel.handleDroppedFiles(providers)
        }
        .toolbar {
            ToolbarItem(placement: .principal) {
                Spacer()
            }
            ToolbarItemGroup(placement: .primaryAction) {
                toolbarContent
            }
        }
    }
    
    // MARK: - Background
    
    private var background: some View {
        Group {
            if viewModel.isDarkMode {
                Color(red: 49.0 / 255.0, green: 49.0 / 255.0, blue: 49.0 / 255.0)
            } else {
                Color(red: 0.97, green: 0.97, blue: 0.97)
            }
        }
        .ignoresSafeArea()
    }
    
    // MARK: - Empty State
    
    private var emptyState: some View {
        VStack(spacing: 16) {
            Text("Select a note")
                .foregroundStyle(viewModel.isDarkMode ? .white.opacity(0.45) : .black.opacity(0.55))
            
            if viewModel.isDropTargeted {
                Text("Drop file here to edit")
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.blue)
                    .transition(.opacity)
            } else {
                Text("or drop a file to edit")
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(viewModel.isDarkMode ? .white.opacity(0.25) : .black.opacity(0.25))
            }
        }
    }
    
    // MARK: - Editor Content
    
    private var editorContent: some View {
        VStack(spacing: 0) {
            EditorHeaderView()
                .padding(.top, 1)
                .padding(.horizontal, 10)
            
            editor
                .padding(.top, 10)
        }
        .safeAreaInset(edge: .bottom) {
            StatusBarView()
                .frame(maxWidth: .infinity)
                .padding(.top, 2)
                .padding(.bottom, 10)
        }
    }
    
    // MARK: - Editor
    
    private var editor: some View {
        @Bindable var vm = viewModel
        
        return Group {
            #if os(macOS)
            ThickCursorTextEditor(
                text: viewModel.activeTextBinding,
                isDarkMode: viewModel.isDarkMode,
                cursorWidth: viewModel.cursorWidth,
                cursorBlinkEnabled: viewModel.cursorBlinkEnabled,
                cursorAnimationEnabled: viewModel.cursorAnimationEnabled,
                cursorAnimationDuration: viewModel.cursorAnimationDuration,
                fontSize: viewModel.fontSize,
                fontFamily: viewModel.fontFamily,
                searchText: viewModel.searchText,
                autocompleteEnabled: viewModel.autocompleteEnabled,
                autocompleteDelay: viewModel.autocompleteDelay,
                autocompleteOpacity: viewModel.autocompleteOpacity,
                suggestionMode: viewModel.suggestionMode,
                markdownRenderEnabled: viewModel.markdownRenderEnabled,
                horizontalPadding: 20,
                doubleTapNavigationEnabled: viewModel.doubleTapNavigationEnabled,
                doubleTapDelay: viewModel.doubleTapDelay,
                currentSearchIndex: viewModel.currentSearchIndex,
                onSearchMatchesChanged: { count, isComplete in
                    viewModel.updateSearchMatches(count: count, isComplete: isComplete)
                },
                onCursorLineChanged: { line in
                    viewModel.cursorLine = line
                }
            )
            .overlay(alignment: .topLeading) {
                if viewModel.activeText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Text("Write something…")
                        .font(.system(size: viewModel.fontSize, weight: .regular, design: viewModel.fontDesign))
                        .foregroundStyle(viewModel.isDarkMode ? .white.opacity(0.25) : .black.opacity(0.25))
                        .padding(.top, 0)
                        .padding(.leading, 20 + 8)
                        .allowsHitTesting(false)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            #else
            TextEditor(text: viewModel.activeTextBinding)
                .font(.system(size: viewModel.fontSize, weight: .regular, design: viewModel.fontDesign))
                .foregroundStyle(viewModel.isDarkMode ? .white.opacity(0.92) : .black.opacity(0.92))
                .scrollContentBackground(.hidden)
                .background(Color.clear)
                .overlay(alignment: .topLeading) {
                    if viewModel.activeText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        Text("Write something…")
                            .font(.system(size: viewModel.fontSize, weight: .regular, design: viewModel.fontDesign))
                            .foregroundStyle(viewModel.isDarkMode ? .white.opacity(0.25) : .black.opacity(0.25))
                            .padding(.top, 0)
                            .padding(.leading, 8)
                            .allowsHitTesting(false)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            #endif
        }
    }
    
    // MARK: - Toolbar Content
    
    @ViewBuilder
    private var toolbarContent: some View {
        @Bindable var vm = viewModel
        
        // Pomodoro timer
        PomodoroTimerView()
        
        // Markdown render toggle button
        ThemeIconButton(
            systemImage: viewModel.markdownRenderEnabled ? "text.badge.checkmark" : "text.badge.xmark",
            isSelected: viewModel.markdownRenderEnabled,
            action: { vm.markdownRenderEnabled.toggle() },
            tooltip: viewModel.markdownRenderEnabled ? "Markdown: ON (click to disable)" : "Markdown: OFF (click to enable)"
        )
        
        ThemeIconButton(
            systemImage: "pencil",
            isSelected: false,
            action: { viewModel.startRenameSelectedNote() },
            tooltip: "Rename note"
        )
        .disabled(viewModel.selectedNoteID == nil)
        .opacity(viewModel.selectedNoteID == nil ? 0.5 : 1.0)
        
        ThemeIconButton(
            systemImage: "trash",
            isSelected: false,
            action: { viewModel.deleteSelectedNote() },
            tooltip: "Delete note"
        )
        .disabled(viewModel.selectedNoteID == nil)
        .opacity(viewModel.selectedNoteID == nil ? 0.5 : 1.0)
        
        // Search bar
        SearchBarView()
    }
}
