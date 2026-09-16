import SwiftUI

struct ProcessingRecordingsView: View {
    let processor: RecordingProcessor

    var body: some View {
        if !processor.recordings.isEmpty {
            TimelineView(.periodic(from: .now, by: 1)) { context in
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(processor.recordings) { recording in
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Label(recording.startedAt == nil ? "Waiting to process…" : "Processing audio…",
                                      systemImage: "waveform.badge.magnifyingglass")
                                Spacer()
                                Text(recording.elapsed(at: context.date))
                                    .monospacedDigit()
                            }
                            Text(recording.filename)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                                .truncationMode(.middle)
                            ProgressView(value: recording.progress)
                        }
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
            }
        }
    }
}
