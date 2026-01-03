//
//  SearchBarView.swift
//  MonkeyNote
//
//  Created by Assistant on 03/01/26.
//

import SwiftUI

struct SearchBarView: View {
    @Environment(ContentViewModel.self) var viewModel
    
    // Local focus state
    @FocusState private var isSearchFocused: Bool
    
    var body: some View {
        @Bindable var vm = viewModel
        
        HStack(spacing: 6) {
            // Toggle replace button
            replaceToggleButton
            
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
                .font(.system(size: 11))
            
            #if os(macOS)
            FocusableSearchField(
                text: $vm.searchText,
                onSubmit: { 
                    viewModel.navigateToNextMatch() 
                },
                onEscape: { viewModel.closeSearch() }
            )
            .frame(minWidth: 100, maxWidth: 180)
            .onChange(of: viewModel.searchText) { _, _ in
                // Trigger ripgrep search on text change
                viewModel.performGlobalSearch()
            }
            #else
            TextField("Search", text: $vm.searchText)
                .textFieldStyle(.plain)
                .font(.system(size: 12))
                .focused($isSearchFocused)
                .onChange(of: viewModel.searchText) { _, _ in
                    viewModel.performGlobalSearch()
                }
            #endif
            
            // Search option toggles
            searchOptionToggles
            
            // Show results and navigation when searching
            if !viewModel.searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                searchResults
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(viewModel.isDarkMode ? Color.white.opacity(0.08) : Color.black.opacity(0.06))
        )
        .animation(.spring(response: 0.20, dampingFraction: 0.5), value: viewModel.searchText.isEmpty)
    }
    
    // MARK: - Search Option Toggles
    
    private var searchOptionToggles: some View {
        HStack(spacing: 4) {
            // Regex toggle
            Button {
                viewModel.toggleRegexMode()
            } label: {
                Text(".*")
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .frame(width: 20, height: 18)
                    .foregroundStyle(viewModel.searchUseRegex ? .white : .secondary)
                    .background(
                        RoundedRectangle(cornerRadius: 3)
                            .fill(viewModel.searchUseRegex 
                                ? Color.blue 
                                : (viewModel.isDarkMode ? Color.white.opacity(0.1) : Color.black.opacity(0.08)))
                    )
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Use regular expression")
            
            // Case sensitive toggle
            Button {
                viewModel.toggleCaseSensitivity()
            } label: {
                Image(systemName: "textformat.size")
                    .font(.system(size: 9, weight: .semibold))
                    .frame(width: 20, height: 18)
                    .foregroundStyle(viewModel.searchCaseSensitive ? .white : .secondary)
                    .background(
                        RoundedRectangle(cornerRadius: 3)
                            .fill(viewModel.searchCaseSensitive 
                                ? Color.blue 
                                : (viewModel.isDarkMode ? Color.white.opacity(0.1) : Color.black.opacity(0.08)))
                    )
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Match case")
        }
    }
    
    // MARK: - Replace Toggle Button
    
    private var replaceToggleButton: some View {
        @Bindable var vm = viewModel
        
        return Button {
            vm.showReplacePopover.toggle()
        } label: {
            Image(systemName: viewModel.showReplaceMode ? "chevron.down.circle.fill" : "chevron.down.circle")
                .font(.system(size: 11))
                .foregroundStyle(viewModel.showReplaceMode ? .blue : .secondary)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("Toggle replace mode")
        #if os(macOS)
        .popover(isPresented: $vm.showReplacePopover, arrowEdge: .bottom) {
            replacePopoverContent
        }
        #endif
    }
    
    // MARK: - Replace Popover Content
    
    #if os(macOS)
    private var replacePopoverContent: some View {
        @Bindable var vm = viewModel
        
        return VStack(spacing: 8) {
            HStack(spacing: 8) {
                Text("Replace:")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                TextField("Replace with...", text: $vm.replaceText)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12))
                    .frame(width: 160)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 4)
                    .background(
                        RoundedRectangle(cornerRadius: 4)
                            .fill(viewModel.isDarkMode ? Color.white.opacity(0.08) : Color.black.opacity(0.06))
                    )
            }
            
            if !viewModel.searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                HStack(spacing: 8) {
                    Button("Replace") {
                        viewModel.replaceCurrentMatch()
                        vm.showReplaceMode = true
                    }
                    .disabled(viewModel.searchMatchCount == 0)
                    .controlSize(.small)
                    
                    Button("Replace All") {
                        viewModel.replaceAll()
                        vm.showReplaceMode = true
                    }
                    .disabled(viewModel.searchMatchCount == 0)
                    .controlSize(.small)
                    
                    Spacer()
                    
                    Button("Cancel") {
                        vm.showReplacePopover = false
                    }
                    .controlSize(.small)
                }
            }
        }
        .padding(12)
        .frame(width: 260)
    }
    #endif
    
    // MARK: - Search Results
    
    private var searchResults: some View {
        Group {
            // Divider
            Rectangle()
                .fill(viewModel.isDarkMode ? Color.white.opacity(0.2) : Color.black.opacity(0.15))
                .frame(width: 1, height: 14)
                .transition(.opacity.combined(with: .scale(scale: 0.8)))
            
            // Search status
            searchStatus
            
            // Navigation buttons
            navigationButtons
            
            // Close button
            Button {
                viewModel.closeSearch()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 8, weight: .semibold))
                    .frame(width: 18, height: 18)
                    .background(
                        RoundedRectangle(cornerRadius: 3)
                            .fill(viewModel.isDarkMode ? Color.white.opacity(0.1) : Color.black.opacity(0.08))
                    )
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .transition(.opacity.combined(with: .move(edge: .trailing)))
        }
    }
    
    // MARK: - Search Status
    
    private var searchStatus: some View {
        Group {
            if viewModel.isSearching {
                ProgressView()
                    .scaleEffect(0.5)
                    .frame(width: 18, height: 18)
            } else {
                // Show global files count with icon
                let fileCount = viewModel.matchingFilePaths.count
                if fileCount > 0 {
                    HStack(spacing: 2) {
                        Image(systemName: "doc.fill")
                            .font(.system(size: 8))
                        Text("\(fileCount)")
                            .font(.system(size: 10, weight: .medium, design: .monospaced))
                    }
                    .foregroundStyle(.blue)
                }
                
                // Divider between file count and in-document matches
                if viewModel.matchingFilePaths.count > 0 && viewModel.searchMatchCount > 0 {
                    Text("|")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                }
                
                // In-document match navigation (current position / total)
                if viewModel.searchMatchCount > 0 {
                    Text("\(viewModel.currentSearchIndex + 1)/\(viewModel.searchMatchCount)\(viewModel.isSearchComplete ? "" : "+")")
                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                        .foregroundStyle(viewModel.isDarkMode ? .white.opacity(0.7) : .black.opacity(0.7))
                } else if !viewModel.searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && viewModel.matchingFilePaths.isEmpty {
                    Text("No results")
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
            }
        }
        .transition(.opacity.combined(with: .scale(scale: 0.8)))
    }
    
    // MARK: - Navigation Buttons
    
    private var navigationButtons: some View {
        Group {
            Button {
                viewModel.navigateToPreviousMatch()
            } label: {
                Image(systemName: "chevron.up")
                    .font(.system(size: 9, weight: .semibold))
                    .frame(width: 18, height: 18)
                    .background(
                        RoundedRectangle(cornerRadius: 3)
                            .fill(viewModel.isDarkMode ? Color.white.opacity(0.1) : Color.black.opacity(0.08))
                    )
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(viewModel.searchMatchCount == 0)
            .transition(.opacity.combined(with: .move(edge: .trailing)))
            
            Button {
                viewModel.navigateToNextMatch()
            } label: {
                Image(systemName: "chevron.down")
                    .font(.system(size: 9, weight: .semibold))
                    .frame(width: 18, height: 18)
                    .background(
                        RoundedRectangle(cornerRadius: 3)
                            .fill(viewModel.isDarkMode ? Color.white.opacity(0.1) : Color.black.opacity(0.08))
                    )
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(viewModel.searchMatchCount == 0)
            .transition(.opacity.combined(with: .move(edge: .trailing)))
        }
    }
}
