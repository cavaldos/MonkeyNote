//
//  ThemeIconButton.swift
//  Note
//
//  Created by Nguyen Ngoc Khanh on 24/12/25.
//

import SwiftUI

struct ThemeIconButton: View {
    let systemImage: String
    let isSelected: Bool
    let action: () -> Void
    var tooltip: String? = nil
    
    @State private var isHovered: Bool = false

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(isSelected ? Color.primary : Color.primary.opacity(isHovered ? 0.75 : 0.55))
                .frame(width: 22, height: 22)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(isSelected ? Color.primary.opacity(0.18) : Color.primary.opacity(isHovered ? 0.10 : 0.06))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .strokeBorder(isSelected ? Color.primary.opacity(0.25) : Color.clear, lineWidth: 1.5)
                )
                .scaleEffect(isHovered ? 1.05 : 1.0)
                .animation(.easeInOut(duration: 0.15), value: isHovered)
                .animation(.easeInOut(duration: 0.15), value: isSelected)
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            isHovered = hovering
        }
        .help(tooltip ?? (isSelected ? "Enabled" : "Disabled"))
        .accessibilityLabel(tooltip ?? (isSelected ? "Selected" : "Not selected"))
    }
}
