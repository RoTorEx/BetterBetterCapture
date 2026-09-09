//
//  MenuBarStatusViews.swift
//  BetterBetterCapture
//

import SwiftUI

// MARK: - Permission Status Banner

/// A banner showing missing permissions with buttons to open System Settings.
struct PermissionStatusBanner: View {
    let permissionService: PermissionService
    let showMicrophonePermission: Bool

    var body: some View {
        VStack(spacing: 4) {
            HStack(spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                Text("Permissions Required")
                    .font(.system(size: 13, weight: .semibold))
                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.top, 8)

            if permissionService.screenRecordingState != .granted {
                PermissionRow(
                    title: "Screen Recording",
                    isGranted: false
                ) {
                    permissionService.openScreenRecordingSettings()
                }
            }

            if showMicrophonePermission && permissionService.microphoneState != .granted {
                PermissionRow(
                    title: "Microphone",
                    isGranted: false
                ) {
                    permissionService.openMicrophoneSettings()
                }
            }
        }
        .padding(.bottom, 8)
    }
}

/// A single permission row with status and action button.
struct PermissionRow: View {
    let title: String
    let isGranted: Bool
    let action: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: isGranted ? "checkmark.circle.fill" : "xmark.circle.fill")
                    .foregroundStyle(isGranted ? .green : .red)
                    .font(.system(size: 12))

                Text(title)
                    .font(.system(size: 12))
                    .foregroundStyle(.primary)

                Spacer()

                if !isGranted {
                    Text("Open Settings")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
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

// MARK: - Audio Level Meter

/// A small panel showing active audio device names, system volumes, and live level bars.
/// Refreshes device names and volumes on a timer so system volume key changes are reflected.
struct AudioLevelMeterView: View {
    let outputLevel: CGFloat
    let inputLevel: CGFloat
    let outputDeviceName: () -> String
    let inputDeviceName: () -> String
    let outputVolume: () -> Float?
    let inputVolume: () -> Float?
    let showOutput: Bool
    let showInput: Bool

    @State private var displayedOutputDeviceName = ""
    @State private var displayedInputDeviceName = ""
    @State private var displayedOutputVolume: Float?
    @State private var displayedInputVolume: Float?
    @State private var refreshTimer: Timer?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if showOutput {
                LevelMeterRow(
                    icon: "speaker.wave.2",
                    label: displayedOutputDeviceName,
                    level: outputLevel,
                    volume: displayedOutputVolume
                )
            }
            if showInput {
                LevelMeterRow(
                    icon: "mic",
                    label: displayedInputDeviceName,
                    level: inputLevel,
                    volume: displayedInputVolume
                )
            }
        }
        .onAppear {
            refreshAudioInfo()
            refreshTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { _ in
                refreshAudioInfo()
            }
        }
        .onDisappear {
            refreshTimer?.invalidate()
            refreshTimer = nil
        }
    }

    private func refreshAudioInfo() {
        displayedOutputDeviceName = outputDeviceName()
        displayedInputDeviceName = inputDeviceName()
        displayedOutputVolume = outputVolume()
        displayedInputVolume = inputVolume()
    }
}

/// A single labeled level bar with an icon and optional system volume readout.
struct LevelMeterRow: View {
    let icon: String
    let label: String
    let level: CGFloat
    let volume: Float?

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                Text(label)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Spacer()
                if let volume {
                    Text(volume, format: .percent.precision(.fractionLength(0)))
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.secondary)
                }
            }

            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(.gray.opacity(0.2))
                    RoundedRectangle(cornerRadius: 2)
                        .fill(.green)
                        .frame(width: geometry.size.width * level)
                }
            }
            .frame(height: 6)
        }
    }
}

// MARK: - Microphone Disabled Warning

/// A warning banner shown in Audio-only mode when microphone capture is disabled.
struct MicrophoneDisabledWarning: View {
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
            Text("Your microphone is off. Only the other side of the call will be recorded.")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.primary)
                .multilineTextAlignment(.leading)
            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.orange.opacity(0.1))
    }
}
