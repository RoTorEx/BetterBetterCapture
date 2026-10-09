import AppKit
import Foundation
import OSLog
import ScreenCaptureKit

extension RecorderViewModel {
    private func releaseOutputAccess() {
        outputAccessURL?.stopAccessingSecurityScopedResource()
        outputAccessURL = nil
    }

    private func acquireOutputAccess() {
        let directory = settings.outputDirectory
        if directory.startAccessingSecurityScopedResource() { outputAccessURL = directory }
    }

    /// Starts a new recording session
    func startRecording() async {
        guard canStartRecording else {
            logger.warning("Cannot start recording: no content selected or already recording")
            return
        }

        state = .starting
        lastError = nil

        // Dismiss the recording overlay if it's still visible
        recordingOverlay.dismiss()

        do {
            try await selectAudioDisplayIfNeeded()

            logger.info("Starting recording sequence...")

            // Stop any active live preview before starting recording
            logger.info("Stopping any active live preview...")
            await previewService.stopPreview()
            logger.info("Live preview stopped")

            // Determine video size from filter
            if let filter = selectedContentFilter {
                videoSize = await getContentSize(from: filter)
            }
            logger.info("Video size: \(self.videoSize.width)x\(self.videoSize.height)")

            // Access security-scoped output directory before writing
            acquireOutputAccess()

            // Setup asset writer
            let outputURL = try prepareCaptureSession()
            try assetWriter.setup(url: outputURL, settings: settings, videoSize: videoSize)
            try assetWriter.startWriting()
            logger.info("AssetWriter ready")

            // Start camera for Presenter Overlay before capture so the system detects it
            if settings.presenterOverlayEnabled {
                await cameraSession.start(deviceID: settings.selectedCameraID)
            }

            // Start capture with the calculated video size
            logger.info("Starting capture engine...")
            try await captureEngine.startCapture(with: settings, videoSize: videoSize, sourceRect: selectedSourceRect)

            try await confirmCaptureStarted()
            // Re-show the area selection border now that capture has started
            if isAreaSelection, let screenRect = selectedScreenRect {
                selectionBorderFrame.show(screenRect: screenRect)
            }

            // Start timer
            startTimer()

            logger.info("Recording started")

        } catch {
            try? await captureEngine.stopCapture()
            state = .idle
            lastError = error
            preserveSession(error: error)
            cameraSession.stop()
            selectionBorderFrame.dismiss()

            // The writer may already be set up and holding an empty output file. Cancel it
            // before releasing the output directory, since that is where the file lives.
            assetWriter.cancel()
            releaseOutputAccess()

            // lastError has no UI representation, so every start failure has to be surfaced
            // as a notification - otherwise the record button silently does nothing.
            notificationService.sendRecordingStartFailedNotification(error: error)

            // The selection points at a display that is gone, so drop it. The next recording
            // attempt then opens the picker instead of failing the same way again.
            if error as? CaptureError == .selectedDisplayDisconnected {
                await resetSelection()
            }

            logger.error("Failed to start recording: \(error.localizedDescription)")
        }
    }

    /// Stops the current recording session
    func stopRecording() async {
        guard isRecording else { return }

        state = .stopping
        healthMonitor?.cancel()
        healthMonitor = nil
        stopTimer()
        selectionBorderFrame.dismiss()

        do {
            // Stop capture and camera session
            try await captureEngine.stopCapture()
            cameraSession.stop()
            isPresenterOverlayActive = false
            audioLevelMonitor.resetLevels()

            var stoppedSession = captureSession
            if var session = stoppedSession {
                session.state = "processing"
                try? calls.store.save(session)
                stoppedSession = session
            }
            let stoppedWriter = assetWriter
            let stoppedAudioOnly = settings.recordAudioOnly
            let accessURL = outputAccessURL
            // Close and sync recovery audio before making capture controls available.
            try stoppedWriter.checkpointRecovery()
            outputAccessURL = nil
            captureSession = nil
            let filename = stoppedWriter.outputURL?.lastPathComponent ?? "Recording"
            assetWriter = AssetWriter(audioLevelMonitor: audioLevelMonitor)
            captureEngine.sampleBufferDelegate = assetWriter
            enqueueProcessing(writer: stoppedWriter, audioOnly: stoppedAudioOnly,
                              accessURL: accessURL, session: stoppedSession, filename: filename)
            state = .idle
            recordingDuration = 0
        } catch {
            state = .idle
            lastError = error
            preserveSession(error: error)
            cameraSession.stop()
            assetWriter.cancel()
            audioLevelMonitor.resetLevels()
            releaseOutputAccess()
            notificationService.sendRecordingFailedNotification(error: error)
            logger.error("Failed to stop recording: \(error.localizedDescription)")
        }
    }

    private func preserveSession(error: Error) {
        guard var session = captureSession else { return }
        session.state = "interrupted"
        session.error = error.localizedDescription
        try? calls.store.save(session)
        captureSession = nil
    }

    private func monitorCaptureHealth() {
        healthMonitor = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(200))
                guard !Task.isCancelled, let self, self.isRecording else { return }
                if let error = self.assetWriter.captureHealth.error {
                    self.lastError = error
                    await self.stopRecording()
                    return
                }
            }
        }
    }

    private func selectAudioDisplayIfNeeded() async throws {
        // Auto-select the main display for audio-only recording so the user
        // does not have to pick content manually. ScreenCaptureKit still
        // requires a content filter even when only audio is captured.
        if settings.recordAudioOnly && selectedContentFilter == nil {
            let content = try await SCShareableContent.current

            guard let display = content.displays.first else {
                throw CaptureError.noContentFilterSelected
            }

            let filter = SCContentFilter(display: display, excludingWindows: [])
            selectedContentFilter = filter
            try await captureEngine.updateFilter(filter)
            logger.info("Auto-selected main display for audio-only recording")
        }

    }

    private func prepareCaptureSession() throws -> URL {
        let session: CaptureSession
        do {
            session = try calls.store.begin(directory: settings.captureOutputDirectory(), name: calls.name, profile: calls.profile)
            storageNotice = nil
        } catch {
            releaseOutputAccess()
            let fallback = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
                .appending(path: "Recordings")
            session = try calls.store.begin(directory: fallback, name: calls.name, profile: calls.profile)
            storageNotice = "Output folder unavailable. Recording is saved in " + fallback.path
        }
        captureSession = session
        let filename = settings.generateOutputURL().lastPathComponent
        return session.directory.appending(path: filename)
    }

    private func confirmCaptureStarted() async throws {
        // The UI must not claim recording until an actual sample has reached storage.
        let deadline = Date().addingTimeInterval(10)
        while !assetWriter.captureHealth.ready {
            if let error = assetWriter.captureHealth.error { throw error }
            guard Date() < deadline else {
                throw NSError(domain: "Capture", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "No captured data reached storage. Check capture permissions and devices."])
            }
            try await Task.sleep(for: .milliseconds(50))
        }
        state = .recording
        if var session = captureSession {
            session.state = "recording"
            try? calls.store.save(session)
            captureSession = session
        }
        monitorCaptureHealth()

    }

    private func enqueueProcessing(writer: AssetWriter, audioOnly: Bool, accessURL: URL?,
                                   session: CaptureSession?, filename: String) {
        recordingProcessor.enqueue(filename: filename) { [weak self] progress in
            defer { accessURL?.stopAccessingSecurityScopedResource() }
            do {
                let (url, frames) = try await writer.finishWriting(progress: progress)
                guard let self else { return }
                if var session = session {
                    session.savedFile = url
                    session.state = "saved"
                    try? self.calls.store.save(session)
                    // Transcription never holds up capture or final audio processing.
                    Task { await self.calls.process(session) }
                }
                if frames == 0 && !audioOnly {
                    self.notificationService.sendRecordingMissingVideoNotification(fileURL: url)
                } else {
                    self.notificationService.sendRecordingSavedNotification(fileURL: url)
                }
            } catch {
                writer.cancel()
                self?.lastError = error
                if var session = session {
                    session.state = "interrupted"
                    session.error = error.localizedDescription
                    try? self?.calls.store.save(session)
                }
                self?.notificationService.sendRecordingFailedNotification(error: error)
            }
        }
    }
}
