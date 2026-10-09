import AppKit
import ScreenCaptureKit

extension RecorderViewModel {
    enum RecordingToggleAction: Equatable {
        case start, stop, none
    }

    enum RecordingState: Equatable {
        case idle
        case starting
        case recording
        case stopping

        var isRecording: Bool { self == .recording }
        var isStopping: Bool { self == .stopping }
        var isBusy: Bool { self != .idle }

        var toggleAction: RecordingToggleAction {
            switch self {
            case .idle: .start
            case .recording: .stop
            case .starting, .stopping: .none
            }
        }

    }

    var isStopping: Bool { state.isStopping }
    var isBusy: Bool { state.isBusy }
    var isRecording: Bool { state.isRecording }
    var isAreaSelection: Bool { selectedSourceRect != nil }
    var hasContentSelected: Bool { selectedContentFilter != nil }

    var canStartRecording: Bool {
        guard state == .idle else { return false }
        if settings.recordAudioOnly {
            return settings.captureSystemAudio || settings.captureMicrophone
        }
        return selectedContentFilter != nil
    }

    var formattedDuration: String {
        let hours = Int(recordingDuration) / 3600
        let minutes = (Int(recordingDuration) % 3600) / 60
        let seconds = Int(recordingDuration) % 60
        return hours > 0
            ? String(format: "%d:%02d:%02d", hours, minutes, seconds)
            : String(format: "%02d:%02d", minutes, seconds)
    }

    var systemAudioDeviceName: String {
        AudioLevelMonitor.defaultOutputDeviceName()
    }

    var microphoneDeviceName: String {
        guard let id = settings.selectedMicrophoneID,
              let device = audioDeviceService.availableDevices.first(where: { $0.id == id }) else {
            return AudioLevelMonitor.defaultInputDeviceName()
        }
        return device.name
    }

    func getContentSize(from filter: SCContentFilter) async -> CGSize {
        let applyScale = settings.captureNativeResolution
        if let sourceRect = selectedSourceRect {
            let scale = CGFloat(filter.pointPixelScale)
            return CGSize(
                width: applyScale ? sourceRect.width * scale : sourceRect.width,
                height: applyScale ? sourceRect.height * scale : sourceRect.height
            )
        }

        let rect = filter.contentRect
        let scale = CGFloat(filter.pointPixelScale)
        if rect.width > 0 && rect.height > 0 {
            return CGSize(
                width: applyScale ? rect.width * scale : rect.width,
                height: applyScale ? rect.height * scale : rect.height
            )
        }

        guard let screen = NSScreen.main else { return CGSize(width: 1920, height: 1080) }
        return CGSize(
            width: applyScale ? screen.frame.width * screen.backingScaleFactor : screen.frame.width,
            height: applyScale ? screen.frame.height * screen.backingScaleFactor : screen.frame.height
        )
    }
}
