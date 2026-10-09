//
//  RecorderViewModel.swift
//  BetterBetterCapture
//
//  Created by Joshua Sattler on 29.01.26.
//

import Foundation
import ScreenCaptureKit
import AppKit
import OSLog

/// The main view model managing recording state and coordination between services
@MainActor
@Observable
final class RecorderViewModel {

    // MARK: - Recording State

    // MARK: - Published Properties

    var state: RecordingState = .idle
    var recordingDuration: TimeInterval = 0
    var lastError: Error?
    var selectedContentFilter: SCContentFilter?

    /// The source rectangle for area selection (in display points, top-left origin)
    private(set) var selectedSourceRect: CGRect?

    /// The selected area in screen coordinates (bottom-left origin), used for the border frame overlay
    var selectedScreenRect: CGRect?

    /// The screen on which the area selection was made
    private var selectedScreen: NSScreen?

    /// Whether Presenter Overlay is currently active (camera composited into stream)
    var isPresenterOverlayActive = false

    // MARK: - Dependencies

    let settings: SettingsStore
    let audioDeviceService: AudioDeviceService
    let cameraDeviceService: CameraDeviceService
    let previewService: PreviewService
    let notificationService: NotificationService
    let permissionService: PermissionService
    let audioLevelMonitor: AudioLevelMonitor
    let captureEngine: CaptureEngine
    let calls = CallWorkflow()
    var captureSession: CaptureSession?
    var healthMonitor: Task<Void, Never>?
    var storageNotice: String?
    let recordingProcessor: RecordingProcessor
    var outputAccessURL: URL?
    var assetWriter: AssetWriter
    let cameraSession = CameraSession()

    let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "BetterBetterCapture", category: "RecorderViewModel")

    // MARK: - Private Properties

    private var recordingTimer: Timer?
    private var recordingStartTime: Date?
    var videoSize: CGSize = .zero
    private let areaSelectionOverlay = AreaSelectionOverlay()
    let selectionBorderFrame = SelectionBorderFrame()
    let recordingOverlay = RecordingOverlayCoordinator()

    // MARK: - Initialization

    convenience init() {
        self.init(settings: SettingsStore())
    }

    init(settings: SettingsStore, recordingProcessor: RecordingProcessor? = nil) {
        self.recordingProcessor = recordingProcessor ?? RecordingProcessor()
        self.settings = settings
        self.audioDeviceService = AudioDeviceService()
        self.cameraDeviceService = CameraDeviceService()
        self.previewService = PreviewService()
        self.notificationService = NotificationService(settings: settings)
        self.permissionService = PermissionService()
        self.audioLevelMonitor = AudioLevelMonitor()
        self.captureEngine = CaptureEngine()
        self.assetWriter = AssetWriter(audioLevelMonitor: audioLevelMonitor)

        captureEngine.delegate = self
        captureEngine.sampleBufferDelegate = assetWriter
        previewService.delegate = self
    }

    // MARK: - Permission Methods

    /// Requests required permissions on app launch
    /// Only requests microphone permission if microphone capture is enabled
    func requestPermissionsOnLaunch() async {
        await permissionService.requestPermissions(includeMicrophone: settings.captureMicrophone)
    }

    /// Refreshes the current permission states
    func refreshPermissions() {
        permissionService.updatePermissionStates()
    }

    // MARK: - Public Methods

    /// Toggles the recording state. If no content is selected, triggers the appropriate
    /// selection flow based on the user's content selection mode preference.
    func toggleRecording() async {
        switch state.toggleAction {
        case .stop:
            await stopRecording()
        case .start where hasContentSelected:
            await startRecording()
        case .start:
            // No content selected — trigger selection based on the user's preferred mode
            switch ContentSelectionMode.current {
            case .pickContent:
                presentPicker()
            case .selectArea:
                await presentAreaSelection()
            }
        case .none:
            logger.info("Ignoring recording toggle while finalization is already in progress")
        }
    }

    /// Presents the system content sharing picker
    func presentPicker() {
        captureEngine.presentPicker()
    }

    /// Presents the area selection overlay on the display under the cursor
    func presentAreaSelection() async {
        // Dismiss any existing border frame so it doesn't overlap the selection overlay
        selectionBorderFrame.dismiss()

        guard let result = await areaSelectionOverlay.present() else {
            logger.info("Area selection cancelled")
            return
        }

        // Show the border frame immediately so the user sees the selection outline
        selectionBorderFrame.show(screenRect: result.screenRect)

        // Find the corresponding SCDisplay for the selected screen
        do {
            let content = try await SCShareableContent.current
            let screenNumber = result.screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID

            guard let display = content.displays.first(where: { $0.displayID == screenNumber }) else {
                logger.error("Could not find SCDisplay for selected screen")
                return
            }

            // Create a content filter for the full display
            let filter = SCContentFilter(display: display, excludingWindows: [])

            // Convert screen rect (NSScreen coordinates, bottom-left origin) to
            // sourceRect (display coordinates, top-left origin)
            let displayHeight = CGFloat(display.height)
            let screenOrigin = result.screen.frame.origin

            let localX = result.screenRect.origin.x - screenOrigin.x
            let localY = result.screenRect.origin.y - screenOrigin.y

            // Flip Y: NSScreen has origin at bottom-left, sourceRect uses top-left
            let flippedY = displayHeight - localY - result.screenRect.height

            // Snap dimensions to even pixel counts for codec compatibility
            let scale = result.screen.backingScaleFactor
            let pixelWidth = result.screenRect.width * scale
            let pixelHeight = result.screenRect.height * scale
            let evenPixelWidth = ceil(pixelWidth / 2) * 2
            let evenPixelHeight = ceil(pixelHeight / 2) * 2

            let sourceRect = CGRect(
                x: localX,
                y: flippedY,
                width: evenPixelWidth / scale,
                height: evenPixelHeight / scale
            )

            // Clear any existing picker selection (mutually exclusive)
            captureEngine.clearSelection()

            // Store the area selection and set the filter on the capture engine
            selectedSourceRect = sourceRect
            selectedScreenRect = result.screenRect
            selectedScreen = result.screen
            selectedContentFilter = filter
            try await captureEngine.updateFilter(filter)

            logger.info("Area selected: sourceRect=\(sourceRect.debugDescription), display=\(display.displayID)")

            // Update preview with the display filter and source rect
            await previewService.setContentFilter(filter, sourceRect: sourceRect)

            // Show the recording overlay on the screen where the area was selected
            recordingOverlay.show(viewModel: self, screen: selectedScreen)

        } catch {
            selectionBorderFrame.dismiss()
            logger.error("Failed to get shareable content for area selection: \(error.localizedDescription)")
        }
    }

    /// Resets the capture selection, removing the border frame and clearing state
    ///
    /// Covers both area and picker selections, so the capture engine's filter is cleared
    /// alongside the view model's - otherwise the engine keeps a filter the UI no longer shows.
    func resetSelection() async {
        selectedSourceRect = nil
        selectedScreenRect = nil
        selectedScreen = nil
        selectedContentFilter = nil
        captureEngine.clearSelection()
        selectionBorderFrame.dismiss()
        recordingOverlay.dismiss()
        await previewService.stopPreview()
        previewService.clearPreview()
    }

    /// Starts the live preview stream (call when menu bar window opens)
    func startPreview() async {
        guard !isRecording else { return }
        await previewService.startPreview()
    }

    /// Stops the live preview stream (call when menu bar window closes)
    func stopPreview() async {
        await previewService.stopPreview()
    }

    // MARK: - Timer Management

    func startTimer() {
        recordingStartTime = Date()
        recordingDuration = 0

        recordingTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, let startTime = self.recordingStartTime else { return }
                self.recordingDuration = Date().timeIntervalSince(startTime)
            }
        }
    }

    func stopTimer() {
        recordingTimer?.invalidate()
        recordingTimer = nil
        recordingStartTime = nil
    }

}

// MARK: - CaptureEngineDelegate

extension RecorderViewModel: CaptureEngineDelegate {

    func captureEngine(_ engine: CaptureEngine, didUpdateFilter filter: SCContentFilter) {
        // Clear any area selection (picker and area selections are mutually exclusive)
        selectedSourceRect = nil
        selectedScreenRect = nil
        selectedScreen = nil
        selectionBorderFrame.dismiss()

        selectedContentFilter = filter
        logger.info("Content filter updated")

        // Capture a static thumbnail for the preview
        Task {
            await previewService.setContentFilter(filter)
        }

        // Show the recording overlay for screen recordings. In audio-only mode the
        // overlay is not useful and would confuse the user into thinking video is captured.
        if !settings.recordAudioOnly {
            recordingOverlay.show(viewModel: self, screen: selectedScreen)
        }
    }

    func captureEngine(_ engine: CaptureEngine, didStopWithError error: Error?) {
        // Check if user clicked "Stop Sharing" in the menu bar
        let isUserStopped = (error as? SCStreamError)?.code == .userStopped

        if let error, !isUserStopped {
            lastError = error
            logger.error("Capture stopped with error: \(error.localizedDescription)")
        }

        // Clean up if we were recording
        if isRecording {
            if isUserStopped {
                // User clicked "Stop Sharing" - gracefully save the recording
                logger.info("User stopped sharing via system UI, saving recording...")
                Task {
                    await stopRecording()
                }
            } else {
                // Stream error during recording - try to save what we have
                logger.warning("Stream stopped unexpectedly, attempting to save recording...")
                Task {
                    await stopRecording()
                }
            }
        }
    }

    func captureEngine(_ engine: CaptureEngine, presenterOverlayDidChange isActive: Bool) {
        isPresenterOverlayActive = isActive
        logger.info("Presenter Overlay \(isActive ? "activated" : "deactivated")")
    }

    func captureEngineDidCancelPicker(_ engine: CaptureEngine) {
        logger.info("Picker was cancelled, clearing selection and preview")

        // Clear the selected content filter
        selectedContentFilter = nil

        // Dismiss the overlay if it was shown after a previous selection
        recordingOverlay.dismiss()

        // Stop and clear the preview
        Task {
            await previewService.cancelCapture()
            previewService.clearPreview()
        }
    }
}

// MARK: - PreviewServiceDelegate

extension RecorderViewModel: PreviewServiceDelegate {

    func previewServiceDidStopByUser(_ service: PreviewService) {
        logger.info("User stopped sharing via system UI, clearing selection")

        // Clear the selection
        selectedContentFilter = nil

        // Clear the content filter in capture engine and deactivate picker
        captureEngine.clearSelection()
        captureEngine.deactivatePicker()
    }
}
