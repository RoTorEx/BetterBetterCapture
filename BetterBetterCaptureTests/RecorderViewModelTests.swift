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
            RecordingStateExpectation(.starting, .none),
            RecordingStateExpectation(.recording, .stop, isRecording: true),
            RecordingStateExpectation(.stopping, .none, isStopping: true)
        ]

        for expectation in states {
            let state = expectation.state
            #expect(state.toggleAction == expectation.toggleAction)
            #expect(state.isBusy == (state != .idle))
            #expect(state.isRecording == expectation.isRecording)
            #expect(state.isStopping == expectation.isStopping)
        }
    }

}

private struct RecordingStateExpectation {
    let state: RecorderViewModel.RecordingState
    let toggleAction: RecorderViewModel.RecordingToggleAction
    var isRecording = false
    var isStopping = false

    init(
        _ state: RecorderViewModel.RecordingState,
        _ toggleAction: RecorderViewModel.RecordingToggleAction,
        isRecording: Bool = false,
        isStopping: Bool = false
    ) {
        self.state = state
        self.toggleAction = toggleAction
        self.isRecording = isRecording
        self.isStopping = isStopping
    }
}
