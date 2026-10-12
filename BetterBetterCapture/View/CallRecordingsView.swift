import AppKit
import SwiftUI

struct CallRecordingsView: View {
    @Bindable var calls: CallWorkflow
    @Environment(\.dismiss) private var dismiss
    let isBusy: Bool
    let isStopping: Bool

    var body: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 8) {
                TextField("Call name (optional)", text: $calls.name)
                    .textFieldStyle(.roundedBorder).disabled(isBusy)
                Picker("Destination", selection: $calls.profile) {
                    Text("Unassigned — save locally").tag("")
                    ForEach(calls.profiles) { Text($0.id).tag($0.id) }
                }
                .disabled(isStopping)
                Toggle("Transcript", isOn: $calls.transcribe)
                    .toggleStyle(.checkbox).disabled(isStopping)
                if calls.integrationError != nil {
                    Text("Voxray unavailable. Recording still works.")
                        .font(.caption).foregroundStyle(.secondary)
                    Button("Reconnect Voxray") { Task { await calls.refresh() } }
                }
                if !calls.store.sessions.isEmpty {
                    Divider().padding(.vertical, 4)
                    Text("Recordings").font(.headline)
                }
                ForEach(calls.store.sessions) { session in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(session.name.isEmpty ? "Recording" : session.name).font(.caption.bold())
                        Text(label(session)).font(.caption).foregroundStyle(.secondary)
                        if let error = session.error { Text(error).font(.caption2).foregroundStyle(.orange) }
                        HStack {
                            Button("Open original") {
                                let folder = calls.store.access(session)
                                let scoped = folder.startAccessingSecurityScopedResource()
                                NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: folder.path)
                                if scoped { folder.stopAccessingSecurityScopedResource() }
                            }
                            if session.state == "interrupted" {
                                Button("Recover audio") { Task { await calls.recover(session) } }
                            } else if let transcript = session.transcript {
                                Button("Transcript") { NSWorkspace.shared.open(transcript) }
                            } else if session.savedFile != nil && session.state != "filed" {
                                Button(session.profile.isEmpty ? "Process" : "Retry") {
                                    Task { await calls.process(session) }
                                }
                                .disabled(calls.activeJobs.contains(session.id) || (session.profile.isEmpty && calls.profile.isEmpty))
                            }
                        }
                        .font(.caption)
                    }
                    .padding(.vertical, 4)
                }
            }
        } label: {
            Text("Voxray (\(calls.version ?? "version unavailable"))")
                .font(.headline)
        }
        .padding(16)
        .task { await calls.refresh() }
        .onExitCommand { dismiss() }
    }

    private func label(_ session: CaptureSession) -> String {
        switch session.state {
        case "ready": "Recording saved · Transcript ready"
        case "filed": "Recording saved · Filed without transcript"
        case "saved": "Recording saved"
        case "transcribing": "Recording saved · Transcribing…"
        case "processing": "Original captured · Processing audio…"
        case "interrupted": "Interrupted · Originals preserved"
        case "starting": "Starting capture…"
        default: "Recording…"
        }
    }
}
