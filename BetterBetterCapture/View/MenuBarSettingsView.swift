//
//  MenuBarSettingsView.swift
//  BetterBetterCapture
//
//  Created by Joshua Sattler on 02.02.26.
//

import SwiftUI

// MARK: - Menu Bar Divider

/// A styled divider for menu bar
struct MenuBarDivider: View {
    var body: some View {
        Divider()
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
    }
}

// MARK: - Device Row

/// A device selection row with icon in circle, native macOS style
struct DeviceRow: View {
    let name: String
    let icon: String
    let isSelected: Bool
    let onSelect: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 12) {
                // Icon in circle
                ZStack {
                    Circle()
                        .fill(isSelected ? .blue.opacity(0.8) : .gray.opacity(0.3))
                        .frame(width: 24, height: 24)

                    Image(systemName: icon)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(isSelected ? .white : .primary)
                }

                // Name
                Text(name)
                    .font(.system(size: 13))
                    .foregroundStyle(.primary)

                Spacer()

                // Checkmark when selected
                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.blue)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 4)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .background(
            RoundedRectangle(cornerRadius: 4)
                .fill(isHovered ? .gray.opacity(0.1) : .clear)
                .padding(.horizontal, 4)
        )
        .onHover { hovering in
            isHovered = hovering
        }
    }
}
