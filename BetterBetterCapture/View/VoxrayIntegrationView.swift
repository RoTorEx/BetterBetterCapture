import SwiftUI

struct VoxrayIntegrationView: View {
    @Bindable var calls: CallWorkflow
    let isAudioOnly: Bool
    let isStopping: Bool
    private var processingDisabled: Bool { isStopping || calls.profile.isEmpty }

    var body: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 8) {
                TextField("Call name (optional)", text: $calls.name)
                    .textFieldStyle(.roundedBorder).disabled(processingDisabled)
                Picker("Destination", selection: $calls.profile) {
                    Text("Unassigned — save locally").tag("")
                    ForEach(calls.profiles) { Text($0.id).tag($0.id) }
                }
                .disabled(isStopping)
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 16) { processingOptions }
                    VStack(alignment: .leading, spacing: 8) { processingOptions }
                }
                if calls.profile.isEmpty {
                    Text("Saved locally. No Voxray processing.")
                        .font(.caption).foregroundStyle(.secondary)
                } else if !isAudioOnly {
                    Text("Video captures always file audio; enable to also keep video in the call folder.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                if calls.integrationError != nil {
                    Text("Voxray unavailable. Recording still works.")
                        .font(.caption).foregroundStyle(.secondary)
                    Button("Reconnect Voxray") { Task { await calls.refresh() } }
                }
            }
        } label: {
            Text("Voxray (\(calls.version ?? "version unavailable"))")
                .font(.headline)
        }
        .padding(16)
        .task { await calls.refresh() }
    }

    @ViewBuilder private var processingOptions: some View {
        Toggle("Transcript", isOn: $calls.transcribe)
            .toggleStyle(.checkbox).disabled(processingDisabled)
            .fixedSize(horizontal: true, vertical: false)
        if !isAudioOnly {
            Toggle("Keep video", isOn: $calls.keepVideo)
                .toggleStyle(.checkbox).disabled(processingDisabled)
                .fixedSize(horizontal: true, vertical: false)
        }
    }
}
