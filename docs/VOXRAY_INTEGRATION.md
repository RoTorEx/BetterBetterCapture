# Capture and Voxray ownership

The recorder captures in its own process. The sandboxed application owns its
writer, source containers, lossless system/microphone CAF fragments, serial
final-audio processing, and session history. The nonsandboxed, Apple
Development-signed embedded XPC service owns only a fixed adapter to
`~/.x-cli-voxray/bin/voxray`. It launches programs directly with arguments,
never through a shell. Its allowlist is version, profiles, submit, status and run.
The version adapter reads the CLI's existing JSON version command and normalizes
it into the bridge envelope. The UI labels the Voxray block with that installed
version; failure to discover it does not prevent profile loading or capture.
No XPC operation can stop capture or delete an original.

The Integrations page inside the menu-bar panel offers a name and a Voxray profile, including an
unassigned local recording. The name and profile remain editable during capture in both
recording modes. Stop freezes their current values before asynchronous shutdown
and finalization; subsequent menu changes apply to later captures. Clearing the
profile before Stop keeps that capture local, even if a profile is selected
while it finalizes. It can be filed later through the standalone Voxray CLI.
After Stop accepts a capture, the Integrations controls reset to an empty name,
Unassigned destination, Transcript on and Keep video off for the next recording.
Unassigned saves to BetterBetterCapture's configured output folder without
submitting anything to Voxray; selecting a profile with Transcript off still
imports audio into that profile.
The Keep video checkbox defaults off and is also frozen at Stop. It adds a
video copy to the Voxray call folder while retaining canonical audio for
transcription. It never deletes BBC originals. The Transcript checkbox is also editable before/during capture and frozen at
Stop. It defaults to enabled to preserve existing behavior and is saved with
the session; later menu changes cannot alter queued work or accepted retries.
Profile discovery follows TOML declaration order, with default first; the UI
keeps that sequence and places Unassigned before it. Discovery failure never disables recording. Each
capture keeps its technical files in `_CaptureData/<UUID>` under the selected
output directory, separate from the eventual call name. Finished audio or video
appears directly in the output directory with a unique timestamp and capture ID.
Recovery exports also appear there. Existing UUID folders directly under the
output directory remain readable. If that output folder cannot be created, capture
falls back to the app's Application Support/Recordings and shows that path.
If neither destination works, Start fails visibly. Metadata failures do not
prevent media capture in an otherwise writable folder.

Starting is distinct from recording: the UI waits for capture startup and the
first successful audio-journal checkpoint (or first synchronized video write
when no audio source is enabled). Disk errors are polled during capture and
surface immediately. The first audio write is checkpointed; subsequent CAF
fragments close and synchronize at approximately two seconds of source audio,
with a final checkpoint at Stop. Hardware synchronization and directory-entry
synchronization are requested; unsupported hardware flush falls back to fsync.
An app crash stops capture and leaves the captured portion. It cannot continue
capturing after its own process dies, and no software can guarantee recovery
from failed storage hardware or preserve an uncommitted tail during power loss.

Raw containers and PCM fragments are retained after successful final processing
and Voxray completion. Delete them explicitly in Finder when no longer needed;
there is no automatic retention cleanup. Final audio is another copy. A failed
container-preservation rename does not invoke AVAssetWriter cancellation that
would delete the original.

Session records live in Application Support/CaptureSessions, with a second
`session.json` inside each recording folder. The folder bookmark preserves
access after relaunch. Restart marks unfinished captures as interrupted. The Integrations page shows only Voxray settings, with no recording list or
per-recording actions. Recovery support is retained internally and can export a new `Recovered-UUID.m4a` using the
separate source fragments and their recorded offsets, preserving originals.
Malformed registry entries are retained; folder metadata can rediscover missing
registry entries. Older loose recordings are not migrated automatically.

After a finalized audio/video file is synchronized, a separate task submits its
UUID, exact path, capture time in Europe/Warsaw, profile and name to Voxray.
Capture and the serial audio-processing queue do not await transcription.
Persistent session states distinguish original captured, final recording saved and transcript
ready. Failed jobs remain saved and can be retried with `voxray jobs run`. Accepted jobs can retry from
Voxray's snapshot even after its current config changes. Unassigned recordings
can be imported later with the standalone Voxray CLI.
Feedback remains an explicit separate Voxray command.

For an assigned profile, the Transcript checkbox chooses import-only or import
plus transcription. Import-only completes with the `stored` job stage and a
persisted `filed` state. It never invokes MacWhisper.
Screen/video capture keeps the recorder's original video and its finalized copy;
Voxray extracts audio for its call folder, optionally keeps video there, then
transcribes only when requested. Refresh reconciles completed saved jobs with
Voxray without resubmitting or rerunning them. The standalone
Voxray CLI can import without transcription; it is a separate workflow.

The XPC adapter bounds short requests at 30 seconds and processing at two hours
plus shutdown margin. A client timeout, malformed response, unavailable binary,
helper interruption or unsupported contract leaves recorder originals intact.
The installed older Voxray has no job contract; update it through its separate
release/install procedure before expecting successful automatic transcription.

## Verification

`make check` runs SwiftLint, Xcode unit tests and a finite crash test. The crash
test compiles the production journal, records distinct nonzero PCM source
signals, SIGKILLs that bounded child before Stop, and decodes both sources with
ffmpeg. All child processes terminate, and test files are removed. Unit tests
cover raw retention, destination conflicts, recovery to a new M4A, restart,
metadata failure, synchronization failure, failed handoff/retry, malformed
contracts and timeout/reply races. They do not assert physical disk failure or
live microphone/remote-call capture.

A signed sandbox/XPC feasibility probe verified access to a test recording,
Voxray config, Voxray, MacWhisper CLI and ffmpeg. The full signed application
build and embedded helper pass strict codesign verification. Automated gates
passed 129 application tests and the finite two-source journal SIGKILL test.
Voxray's separate gates passed 81 Rust tests and its real CLI media workflow.

With explicit authorization to launch it, an isolated signed application was
exercised through its actual menu. It used a distinct bundle identifier and
preferences; its helper pointed to a private new CLI with profile destinations
redirected to a test library. Live system audio and MacBook microphone fragments
contained nonzero audio. Killing the XPC helper during capture did not stop the
recorder. Stop produced a playable AAC M4A; real MacWhisper WhisperKit
transcription reached the ready state and the menu displayed transcript ready.
Named Thira and default-named Aveni recordings reached their respective folders
with the capture date converted to Europe/Warsaw.

Killing the recorder during another live capture, then relaunching, displayed
the interrupted state. Recover audio produced a playable 10.47-second M4A while
all 13 original CAF/container files retained their SHA-256 hashes. Temporarily
removing the private CLI made handoff fail visibly while the recovered recording
remained saved. Restoring it and choosing Retry completed real transcription.
The tests used synthetic spoken audio, not a remote meeting; they do not certify
every device, screen/video mode, filesystem or power-loss condition. Self-review
checked capture ownership, atomic publication, source retention and retry.
No release or normal local installation was performed in this stage.
