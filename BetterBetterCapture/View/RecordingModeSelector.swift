import SwiftUI

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
