//
//  BetterBetterCaptureApp.swift
//  BetterBetterCapture
//
//  Created by Joshua Sattler on 29.01.26.
//

import AppKit
import KeyboardShortcuts
import SwiftUI

@main
struct BetterBetterCaptureApp: App {
    @State private var viewModel = RecorderViewModel()
    @State private var updaterService = UpdaterService()
    var body: some Scene {
        // Menu bar extra - the primary interface
        // Using .window style to support custom toggle switches
        MenuBarExtra {
            MenuBarView(viewModel: viewModel)
                .task {
                    await viewModel.requestPermissionsOnLaunch()
                    registerKeyboardShortcuts()
                }
                .onOpenURL { url in
                    handleURL(url)
                }
        } label: {
            MenuBarLabel(viewModel: viewModel)
        }
        .menuBarExtraStyle(.window)

        // Settings window
        Settings {
            SettingsView(
                settings: viewModel.settings,
                updaterService: updaterService,
                audioDeviceService: viewModel.audioDeviceService,
                cameraDeviceService: viewModel.cameraDeviceService
            )
        }
    }

    // MARK: - URL Scheme

    private func handleURL(_ url: URL) {
        guard url.scheme == "betterbettercapture" else { return }

        switch url.host {
        case "toggle":
            Task { @MainActor in
                if viewModel.isRecording {
                    await viewModel.stopRecording()
                } else {
                    switch ContentSelectionMode.current {
                    case .pickContent:
                        viewModel.presentPicker()
                    case .selectArea:
                        await viewModel.presentAreaSelection()
                    }
                }
            }
        case "open-recordings":
            Task { @MainActor in
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
        default:
            break
        }
    }

    // MARK: - Keyboard Shortcuts

    private func registerKeyboardShortcuts() {
        KeyboardShortcuts.onKeyUp(for: .toggleRecording) { [viewModel] in
            Task { @MainActor in
                await viewModel.toggleRecording()
            }
        }

        KeyboardShortcuts.onKeyUp(for: .selectContent) { [viewModel] in
            Task { @MainActor in
                viewModel.presentPicker()
            }
        }

        KeyboardShortcuts.onKeyUp(for: .selectArea) { [viewModel] in
            Task { @MainActor in
                await viewModel.presentAreaSelection()
            }
        }
    }
}

/// The label shown in the menu bar. Uses a static film icon when idle and a
/// red camera or microphone icon while recording, depending on the recording mode.
struct MenuBarLabel: View {
    let viewModel: RecorderViewModel

    var body: some View {
        if let recordingIconName {
            Image(systemName: recordingIconName)
                .foregroundStyle(.red)
        } else {
            Image("MenuBarIcon")
                .renderingMode(.template)
                .resizable()
                .scaledToFit()
                .frame(width: 18, height: 18)
                .foregroundStyle(.primary)
        }
    }

    private var recordingIconName: String? {
        if viewModel.isRecording {
            return viewModel.settings.recordAudioOnly ? "mic.circle.fill" : "video.circle.fill"
        }
        return nil
    }
}
