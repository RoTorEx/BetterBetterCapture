//
//  RecorderViewModelTests.swift
//  BetterBetterCaptureTests
//
//  Created by Joshua Sattler on 28.03.26.
//

import Foundation
import Testing
@testable import BetterBetterCapture

/// Tests for RecorderViewModel's pure derived state and formatting.
///
/// These test the computed properties and initial state without
/// triggering any ScreenCaptureKit or system interactions.
@MainActor
struct RecorderViewModelTests {

    private func withIsolatedViewModel(_ test: (RecorderViewModel) -> Void) {
        let suiteName = "RecorderViewModelTests.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            Issue.record("Could not create isolated user defaults")
            return
        }
        defer { defaults.removePersistentDomain(forName: suiteName) }

        test(RecorderViewModel(settings: SettingsStore(defaults: defaults)))
    }

    // MARK: - formattedDuration

    @Test func formattedDurationAtZero() {
        let viewModel = RecorderViewModel()
        #expect(viewModel.formattedDuration == "00:00")
    }

    // MARK: - Initial State

    @Test func initialStateIsIdle() {
        let viewModel = RecorderViewModel()
        #expect(viewModel.isRecording == false)
        #expect(viewModel.isBusy == false)
    }

    @Test func cannotStartRecordingWithoutContentFilter() {
        withIsolatedViewModel { viewModel in
            #expect(viewModel.canStartRecording == false)
        }
    }

    @Test func hasNoContentSelectedByDefault() {
        let viewModel = RecorderViewModel()
        #expect(viewModel.hasContentSelected == false)
    }

    @Test func isNotAreaSelectionByDefault() {
        let viewModel = RecorderViewModel()
        #expect(viewModel.isAreaSelection == false)
    }

    @Test func presenterOverlayInactiveByDefault() {
        let viewModel = RecorderViewModel()
        #expect(viewModel.isPresenterOverlayActive == false)
    }

    @Test func lastErrorIsNilByDefault() {
        let viewModel = RecorderViewModel()
        #expect(viewModel.lastError == nil)
    }

    @Test func recordingDurationIsZeroByDefault() {
        let viewModel = RecorderViewModel()
        #expect(viewModel.recordingDuration == 0)
    }

    // MARK: - Audio Only Recording

    @Test func canStartAudioOnlyRecordingWithoutContentFilter() {
        withIsolatedViewModel { viewModel in
            viewModel.settings.recordAudioOnly = true
            viewModel.settings.captureSystemAudio = true

            #expect(viewModel.canStartRecording == true)
        }
    }

    @Test func cannotStartAudioOnlyRecordingWithoutAudioSources() {
        withIsolatedViewModel { viewModel in
            viewModel.settings.recordAudioOnly = true
            viewModel.settings.captureSystemAudio = false
            viewModel.settings.captureMicrophone = false

            #expect(viewModel.canStartRecording == false)
        }
    }

    // MARK: - Recording State Matrix

    @Test func everyRecordingStateRoutesToggleSafely() {
        let states = [
            RecordingStateExpectation(.idle, .start),
            RecordingStateExpectation(.recording, .stop, isRecording: true),
            RecordingStateExpectation(.stopping, .none, isStopping: true),
            RecordingStateExpectation(.processing(0), .none, isProcessing: true),
            RecordingStateExpectation(.processing(0.5), .none, isProcessing: true),
            RecordingStateExpectation(.processing(1), .none, isProcessing: true)
        ]

        for expectation in states {
            let state = expectation.state
            #expect(state.toggleAction == expectation.toggleAction)
            #expect(state.isBusy == (state != .idle))
            #expect(state.isRecording == expectation.isRecording)
            #expect(state.isStopping == expectation.isStopping)
            #expect(state.isProcessing == expectation.isProcessing)
        }
    }

    @Test func progressOnlyChangesProcessingStateAndNeverMovesBackward() {
        #expect(RecorderViewModel.RecordingState.idle.updatingProcessingProgress(1) == .idle)
        #expect(RecorderViewModel.RecordingState.recording.updatingProcessingProgress(1) == .recording)
        #expect(RecorderViewModel.RecordingState.stopping.updatingProcessingProgress(1) == .stopping)
        #expect(RecorderViewModel.RecordingState.processing(0.6)
            .updatingProcessingProgress(0.4) == .processing(0.6))
        #expect(RecorderViewModel.RecordingState.processing(0.6)
            .updatingProcessingProgress(2) == .processing(1))
        #expect(RecorderViewModel.RecordingState.processing(0.6)
            .updatingProcessingProgress(.nan) == .processing(0.6))
    }
}

private struct RecordingStateExpectation {
    let state: RecorderViewModel.RecordingState
    let toggleAction: RecorderViewModel.RecordingToggleAction
    var isRecording = false
    var isStopping = false
    var isProcessing = false

    init(
        _ state: RecorderViewModel.RecordingState,
        _ toggleAction: RecorderViewModel.RecordingToggleAction,
        isRecording: Bool = false,
        isStopping: Bool = false,
        isProcessing: Bool = false
    ) {
        self.state = state
        self.toggleAction = toggleAction
        self.isRecording = isRecording
        self.isStopping = isStopping
        self.isProcessing = isProcessing
    }
}
