//
//  MenuBarView.swift
//  BetterBetterCapture
//
//  Created by Joshua Sattler on 29.01.26.
//

import SwiftUI
import ScreenCaptureKit

/// The main menu bar interface for BetterBetterCapture
struct MenuBarView: View {
    @Bindable var viewModel: RecorderViewModel
    @Environment(\.openSettings) private var openSettings
    @Environment(\.dismiss) private var dismiss
    @State private var currentPreview: NSImage?

    private var isRecording: Bool { viewModel.isRecording }

    var body: some View {
        VStack(spacing: 0) {
            // Permission status banner (only when idle)
            if !isRecording,
               viewModel.permissionService.screenRecordingState != .granted ||
                (viewModel.settings.captureMicrophone && viewModel.permissionService.microphoneState != .granted) {
                PermissionStatusBanner(
                    permissionService: viewModel.permissionService,
                    showMicrophonePermission: viewModel.settings.captureMicrophone
                )
                MenuBarDivider()
            }

            // Recording button (stop) or Start button
            if isRecording {
                MenuBarActionButton(
                    title: "Stop Recording",
                    systemImage: "stop.circle",
                    accentColor: .red,
                    isProminent: true
                ) {
                    Task {
                        await viewModel.stopRecording()
                    }
                }
                .padding(.horizontal, 12)
                .padding(.top, 8)
            } else {
                MenuBarActionButton(
                    title: "Start Recording",
                    systemImage: "record.circle",
                    accentColor: .green,
                    isDisabled: !viewModel.canStartRecording,
                    isProminent: true
                ) {
                    Task {
                        await viewModel.startRecording()
                        dismiss()
                    }
                }
                .padding(.horizontal, 12)
                .padding(.top, 8)

                // Recording mode selector (audio-only vs screen + audio)
                RecordingModeSelector(settings: viewModel.settings)
                    .padding(.horizontal, 12)
                    .padding(.top, 6)
                    .disabled(isRecording)
            }

            // Content Selection (only relevant for screen + audio mode)
            if !viewModel.settings.recordAudioOnly {
                VStack(spacing: 0) {
                    MenuBarDivider()

                    ContentSelectionButton(viewModel: viewModel) { dismiss() }
                        .disabled(isRecording)

                    // Preview thumbnail (hidden in audio-only mode since the auto-selected display is not relevant)
                    if viewModel.hasContentSelected {
                        PreviewThumbnailView(
                            previewImage: currentPreview,
                            isLivePreviewActive: viewModel.previewService.isCapturing,
                            onStartLivePreview: {
                                Task {
                                    await viewModel.startPreview()
                                }
                            },
                            onStopLivePreview: {
                                Task {
                                    await viewModel.stopPreview()
                                }
                            }
                        )
                        .onChange(of: viewModel.previewService.previewImage) { _, newImage in
                            currentPreview = newImage
                        }
                        .onAppear {
                            currentPreview = viewModel.previewService.previewImage
                        }

                        Button {
                            Task {
                                await viewModel.resetSelection()
                            }
                        } label: {
                            Text("Reset Selection")
                                .font(.system(size: 13, weight: .medium))
                                .foregroundStyle(.red)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 6)
                                .background(.gray.opacity(0.15), in: .rect(cornerRadius: 6))
                        }
                        .buttonStyle(.plain)
                        .padding(.horizontal, 12)
                        .disabled(isRecording)
                    }
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }

            MenuBarDivider()

            // Settings Sections
            Group {
                VideoSettingsSection(settings: viewModel.settings)

                PresenterOverlaySettingsSection(
                    settings: viewModel.settings,
                    cameraDeviceService: viewModel.cameraDeviceService
                )

                AudioSettingsSection(
                    settings: viewModel.settings,
                    audioDeviceService: viewModel.audioDeviceService
                )
            }
            .disabled(isRecording)

            // Live audio level meter — kept outside the disabled group so it updates during recording
            if viewModel.settings.captureSystemAudio || viewModel.settings.captureMicrophone {
                AudioLevelMeterView(
                    outputLevel: viewModel.audioLevelMonitor.systemAudioLevel,
                    inputLevel: viewModel.audioLevelMonitor.microphoneLevel,
                    showOutput: viewModel.settings.captureSystemAudio,
                    showInput: viewModel.settings.captureMicrophone
                )
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .transition(.opacity.combined(with: .move(edge: .top)))
                .animation(.easeInOut(duration: 0.2), value: viewModel.settings.captureSystemAudio || viewModel.settings.captureMicrophone)
            }

            MenuBarDivider()

            // Bottom Actions
            MenuBarActionButton(title: "Open Output Folder", systemImage: "folder") {
                let settings = viewModel.settings
                let didStart = settings.startAccessingOutputDirectory()
                defer {
                    if didStart {
                        settings.stopAccessingOutputDirectory()
                    }
                }

                let directory = settings.outputDirectory
                try? FileManager.default.createDirectory(
                    at: directory,
                    withIntermediateDirectories: true
                )

                NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: directory.path)
            }

            MenuBarActionButton(title: "Settings...", systemImage: "gear") {
                NSApplication.shared.activate(ignoringOtherApps: true)
                openSettings()
            }

            MenuBarActionButton(title: "Quit...", systemImage: "power") {
                NSApplication.shared.terminate(nil)
            }
            .padding(.bottom, 8)
        }
        .frame(width: 320)
        .background(.ultraThinMaterial)
        .animation(.easeInOut(duration: 0.25), value: viewModel.settings.recordAudioOnly)
    }
}

// MARK: - Menu Bar Action Button

/// A styled action button for menu bar window with hover effect
struct MenuBarActionButton: View {
    let title: String
    var systemImage: String?
    var accentColor: Color = .primary
    var isDisabled: Bool = false
    var isProminent: Bool = false
    let action: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                if let systemImage {
                    ZStack {
                        Circle()
                            .fill(isProminent ? .white.opacity(0.25) : .gray.opacity(0.2))
                            .frame(width: 24, height: 24)

                        Image(systemName: systemImage)
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(isDisabled ? Color.gray.opacity(0.3) : (isProminent ? .white : accentColor.opacity(0.8)))
                    }
                }
                Text(title)
                    .font(.system(size: 13, weight: isProminent ? .semibold : .medium))
                    .foregroundStyle(isDisabled ? Color.gray.opacity(0.5) : (isProminent ? .white : Color.primary))
                Spacer()
            }
            .padding(.horizontal, isProminent ? 10 : 12)
            .padding(.vertical, isProminent ? 6 : 4)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .disabled(isDisabled)
        .background(
            RoundedRectangle(cornerRadius: isProminent ? 10 : 4)
                .fill(backgroundFill)
        )
        .onHover { hovering in
            isHovered = hovering
        }
    }

    private var backgroundFill: Color {
        if isDisabled {
            return isProminent ? .gray.opacity(0.3) : .clear
        }
        if isProminent {
            return isHovered ? accentColor.opacity(0.85) : accentColor
        }
        return isHovered ? accentColor.opacity(0.1) : .clear
    }
}

// MARK: - Content Selection Button

/// A split button that triggers the active content selection mode, with a dropdown chevron to switch modes.
/// The left portion triggers the action; the right chevron opens a dropdown to change the mode.
/// Styled consistently with other menu bar rows.
struct ContentSelectionButton: View {
    let viewModel: RecorderViewModel
    var onDismissPanel: (() -> Void)?
    @AppStorage(ContentSelectionMode.storageKey) private var mode: ContentSelectionMode = .pickContent
    @State private var isDropdownExpanded = false
    @State private var isMainHovered = false
    @State private var isChevronHovered = false

    /// Whether content has been selected via the currently active mode
    private var hasActiveSelection: Bool {
        switch mode {
        case .pickContent:
            viewModel.hasContentSelected && !viewModel.isAreaSelection
        case .selectArea:
            viewModel.isAreaSelection
        }
    }

    private var buttonLabel: String {
        hasActiveSelection ? "Change \(mode.label.split(separator: " ").last, default: "Content")..." : "\(mode.label)..."
    }

    var body: some View {
        VStack(spacing: 0) {
            // Main button row
            HStack(spacing: 0) {
                // Left: action button
                Button {
                    triggerAction()
                } label: {
                    HStack(spacing: 12) {
                        ZStack {
                            Circle()
                                .fill(hasActiveSelection ? .blue.opacity(0.8) : .gray.opacity(0.2))
                                .frame(width: 24, height: 24)

                            Image(systemName: mode.icon)
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(hasActiveSelection ? .white : .primary)
                        }

                        Text(buttonLabel)
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(.primary)

                        Spacer()
                    }
                    .padding(.leading, 12)
                    .padding(.vertical, 4)
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .onHover { hovering in
                    isMainHovered = hovering
                }

                // Right: chevron dropdown toggle
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        isDropdownExpanded.toggle()
                    }
                } label: {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .rotationEffect(.degrees(isDropdownExpanded ? 90 : 0))
                        .frame(width: 28, height: 28)
                        .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .padding(.trailing, 12)
                .onHover { hovering in
                    isChevronHovered = hovering
                }
            }
            .background(
                RoundedRectangle(cornerRadius: 4)
                    .fill((isMainHovered || isChevronHovered) ? .gray.opacity(0.1) : .clear)
                    .padding(.horizontal, 4)
            )

            // Dropdown options
            if isDropdownExpanded {
                VStack(spacing: 0) {
                    DeviceRow(
                        name: ContentSelectionMode.pickContent.label,
                        icon: ContentSelectionMode.pickContent.icon,
                        isSelected: mode == .pickContent
                    ) {
                        mode = .pickContent
                        withAnimation(.easeInOut(duration: 0.2)) {
                            isDropdownExpanded = false
                        }
                    }

                    DeviceRow(
                        name: ContentSelectionMode.selectArea.label,
                        icon: ContentSelectionMode.selectArea.icon,
                        isSelected: mode == .selectArea
                    ) {
                        mode = .selectArea
                        withAnimation(.easeInOut(duration: 0.2)) {
                            isDropdownExpanded = false
                        }
                    }
                }
                .padding(.leading, 12)
                .background(.quaternary.opacity(0.3))
            }
        }
    }

    private func triggerAction() {
        switch mode {
        case .pickContent:
            viewModel.presentPicker()
        case .selectArea:
            onDismissPanel?()
            Task {
                await viewModel.presentAreaSelection()
            }
        }
    }
}

// MARK: - Permission Status Banner

/// A banner showing missing permissions with buttons to open System Settings
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

/// A single permission row with status and action button
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

// MARK: - Recording Mode Selector

/// A two-segment selector shown under the Start Recording button.
/// Switching to Audio mode enables audio-only capture and hides content selection.
struct RecordingModeSelector: View {
    @Bindable var settings: SettingsStore

    private var mode: RecordingMode {
        get {
            settings.recordAudioOnly ? .audio : .screenAndAudio
        }
        nonmutating set {
            settings.recordAudioOnly = (newValue == .audio)
        }
    }

    var body: some View {
        HStack(spacing: 0) {
            ForEach(RecordingMode.allCases) { recordingMode in
                let isSelected = mode == recordingMode

                Button {
                    mode = recordingMode
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: recordingMode.icon)
                            .font(.system(size: 12, weight: .medium))
                        Text(recordingMode.label)
                            .font(.system(size: 12, weight: .semibold))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
                    .foregroundStyle(isSelected ? .white : .primary)
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .fill(isSelected ? Color.accentColor : .clear)
                    )
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(2)
        .background(.gray.opacity(0.15), in: .rect(cornerRadius: 8))
    }
}

// MARK: - Audio Level Meter

/// A small panel showing active audio device names, system volumes, and live level bars.
/// Refreshes device names and volumes on a timer so system volume key changes are reflected.
struct AudioLevelMeterView: View {
    let outputLevel: CGFloat
    let inputLevel: CGFloat
    let showOutput: Bool
    let showInput: Bool

    @State private var outputDeviceName = AudioLevelMonitor.defaultOutputDeviceName()
    @State private var inputDeviceName = AudioLevelMonitor.defaultInputDeviceName()
    @State private var outputVolume: Float?
    @State private var inputVolume: Float?
    @State private var refreshTimer: Timer?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if showOutput {
                LevelMeterRow(
                    icon: "speaker.wave.2",
                    label: outputDeviceName,
                    level: outputLevel,
                    volume: outputVolume
                )
            }
            if showInput {
                LevelMeterRow(
                    icon: "mic",
                    label: inputDeviceName,
                    level: inputLevel,
                    volume: inputVolume
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
        outputDeviceName = AudioLevelMonitor.defaultOutputDeviceName()
        inputDeviceName = AudioLevelMonitor.defaultInputDeviceName()
        outputVolume = AudioLevelMonitor.defaultOutputVolume()
        inputVolume = AudioLevelMonitor.defaultInputVolume()
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

// MARK: - Preview

#Preview {
    MenuBarView(viewModel: RecorderViewModel())
}
