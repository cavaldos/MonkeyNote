//
//  FontPreviewerView.swift
//  MonkeyNote
//
//  Created by Nguyen Ngoc Khanh on 30/12/25.
//

import SwiftUI

struct FontPreviewerView: View {
    @Environment(\.dismiss) private var dismiss
    @AppStorage("note.fontFamily") private var fontFamily: String = "monospaced"
    @AppStorage("note.fontSize") private var fontSize: Double = 28
    
    @State private var searchText: String = ""
    @State private var isDetailedView: Bool = false
    @State private var selectedFont: String = ""
    
    private let sampleTexts = [
        "The quick brown fox jumps over the lazy dog",
        "Hà Nội là thủ đô Việt Nam",
        "0123456789 !@#$%^&*()",
        "ABCDEFGHIJKLMNOPQRSTUVWXYZ",
        "abcdefghijklmnopqrstuvwxyz"
    ]
    
    private var availableFonts: [String] {
        let systemFonts = NSFontManager.shared.availableFontFamilies.sorted()
        return systemFonts
    }
    
    private var filteredFonts: [String] {
        if searchText.isEmpty {
            return availableFonts
        }
        return availableFonts.filter { $0.localizedCaseInsensitiveContains(searchText) }
    }
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Search and controls
                VStack(spacing: 16) {
                    HStack {
                        Image(systemName: "magnifyingglass")
                            .foregroundStyle(.secondary)
                        TextField("Search fonts...", text: $searchText)
                            .textFieldStyle(.plain)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color(.controlBackgroundColor))
                    )
                    
                    HStack {
                        Text("\(filteredFonts.count) fonts")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        
                        Spacer()
                        
                        Toggle("Detailed View", isOn: $isDetailedView)
                            .toggleStyle(.switch)
                            .controlSize(.small)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 20)
                .padding(.bottom, 16)
                
                Divider()
                
                // Font list
                ScrollView {
                    LazyVStack(spacing: 8) {
                        ForEach(filteredFonts, id: \.self) { fontName in
                            FontRow(
                                fontName: fontName,
                                isDetailedView: isDetailedView,
                                sampleTexts: sampleTexts,
                                isSelected: selectedFont == fontName || fontFamily == fontName,
                                onSelect: {
                                    selectedFont = fontName
                                    fontFamily = fontName
                                    dismiss()
                                }
                            )
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 16)
                }
            }
            .navigationTitle("Font Previewer")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
        .frame(minWidth: 600, minHeight: 500)
        .onAppear {
            selectedFont = fontFamily
        }
    }
}

struct FontRow: View {
    let fontName: String
    let isDetailedView: Bool
    let sampleTexts: [String]
    let isSelected: Bool
    let onSelect: () -> Void
    
    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            VStack(alignment: .leading, spacing: 8) {
                // Font name
                Text(fontName)
                    .font(.system(size: 16, weight: .medium, design: .monospaced))
                    .foregroundStyle(.primary)
                
                // Sample text preview
                if isDetailedView {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(Array(sampleTexts.prefix(3)), id: \.self) { sample in
                            Text(sample)
                                .font(.custom(fontName, size: 14))
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }
                } else {
                    Text(sampleTexts[0])
                        .font(.custom(fontName, size: 16))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            
            Spacer()
            
            // Selection indicator
            Button {
                onSelect()
            } label: {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(isSelected ? .blue : .secondary)
                    .font(.system(size: 20))
            }
            .buttonStyle(.plain)
            .help(isSelected ? "Selected" : "Select this font")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(isSelected ? Color.blue.opacity(0.1) : Color(.controlBackgroundColor))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(isSelected ? Color.blue : Color.clear, lineWidth: 1)
                )
        )
        .onHover { isHovering in
            if isHovering {
                NSCursor.pointingHand.set()
            } else {
                NSCursor.arrow.set()
            }
        }
    }
}

#Preview {
    FontPreviewerView()
}