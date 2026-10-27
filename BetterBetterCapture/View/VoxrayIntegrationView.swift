import SwiftUI

struct VoxrayIntegrationView: View {
    @Bindable var calls: CallWorkflow
    let isAudioOnly: Bool
    let isStopping: Bool
    private var processingDisabled: Bool { isStopping || calls.profile.isEmpty }
    private var callNameUnavailableReason: String? {
        if isStopping { return "Call name is locked while the recording finishes saving." }
        if calls.profile.isEmpty { return "Select a destination to name the call." }
        return nil
    }

    var body: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 8) {
                Picker("Destination", selection: $calls.profile) {
                    Text("Unassigned — save locally").tag("")
                    ForEach(calls.profiles) { Text($0.id).tag($0.id) }
                }
                .disabled(isStopping)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Call name (optional)")
                        .foregroundStyle(processingDisabled ? .secondary : .primary)
                    TextField("Call name", text: $calls.name,
                              prompt: Text(processingDisabled ? "Unavailable" : "Enter call name"))
                        .textFieldStyle(.roundedBorder)
                        .disabled(processingDisabled)
                        .opacity(processingDisabled ? 0.5 : 1)
                        .accessibilityHint(callNameUnavailableReason ?? "Editable before and during recording.")
                    if let reason = callNameUnavailableReason {
                        Text(reason).font(.caption).foregroundStyle(.secondary)
                    }
                }
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 16) { processingOptions }
                    VStack(alignment: .leading, spacing: 8) { processingOptions }
                }
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 16) { storageOptions }
                    VStack(alignment: .leading, spacing: 8) { storageOptions }
                }
                if calls.googleDrive && !calls.profile.isEmpty {
                    TextField("Google Drive folder ID", text: $calls.driveFolder)
                        .textFieldStyle(.roundedBorder).disabled(processingDisabled)
                    Text("Defaults come from Voxray. Override the folder for this call.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                if calls.transcriptOnly {
                    Text("Deletes call media, recorder originals and recovery audio after a verified transcript and any requested upload. Recognition accuracy still needs review.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                if calls.profile.isEmpty {
                    Text("Saved locally. No Voxray processing.")
                        .font(.caption).foregroundStyle(.secondary)
                } else if !isAudioOnly {
                    Text("Video captures always file audio; enable to also keep video in the call folder.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                if calls.integrationError != nil {
                    Text(calls.integrationError ?? "Voxray unavailable. Recording still works.")
                        .font(.caption).foregroundStyle(.secondary)
                    Button("Retry Voxray") { Task { await calls.refresh() } }
                }
            }
        } label: {
            Text("Voxray (\(calls.version ?? "version unavailable"))")
                .font(.headline)
        }
        .padding(16)
        .task { await calls.refresh() }
    }

    @ViewBuilder private var storageOptions: some View {
        Toggle("Google Drive", isOn: $calls.googleDrive)
            .toggleStyle(.checkbox).disabled(processingDisabled || !calls.driveSupported)
            .help("Requires Voxray 0.6 or later and personal Google OAuth credentials.")
            .fixedSize(horizontal: true, vertical: false)
        Toggle("Transcript only", isOn: $calls.transcriptOnly)
            .toggleStyle(.checkbox).disabled(processingDisabled || !calls.driveSupported)
            .fixedSize(horizontal: true, vertical: false)
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
