# Product contract

## Scope

- Native menu-bar screen recording for macOS 15.2 or later.
- ProRes 422/4444, HEVC/H.265, and H.264 encoding, including supported alpha and
  HDR workflows.
- Simultaneous system-audio and microphone capture.
- Voice microphone processing is the default: system audio is used as the
  far-end reference for WebRTC AEC3, followed by noise suppression and AGC2.
  Raw mode bypasses voice processing and permits a fixed gain.
- Capture audio is held in a lossless intermediate and encoded once in a serial
  background queue after stop. Final output contains one mixed audio track;
  video is remuxed without a second encode. Each capture has an independent
  writer, settings snapshot and output-directory access for its whole lifetime.
- A visible `-unprocessed.mov` original remains until it is
  explicitly deleted, including after a processed copy is synchronized. Failures
  never overwrite an existing
  destination or intentionally delete captured samples. Output names remain
  unique when recordings start within the same second.
- During capture, separate system/microphone lossless CAF fragments are written
  into a visible `-recovery` folder next to the output. Their filenames contain
  the source and starting offset in seconds. Open `.partial.caf` fragments use
  an unknown-length CAF data chunk and require no final header rewrite to read.
  Fragments close and synchronize after about 2 seconds of source audio, and all
  open fragments synchronize before capture controls return to idle after Stop.
  This interval limits additional disk synchronization work while retaining
  already committed audio during interruption. Power loss can still lose the
  uncommitted tail or data affected by storage failure. Video containers use a
  2-second movie-fragment interval as an additional recovery mechanism; audio
  fragments remain the fallback when the container cannot be read.
  Synchronization requests hardware-cache flushing (`F_FULLFSYNC`) where the
  output volume supports it, with ordinary filesystem synchronization as the
  fallback for unsupported volumes. Real synchronization I/O errors fail visibly.
- Recovery files survive cancellation, successful processing and restart until
  explicit deletion. Persistent session metadata detects interrupted captures; originals and recovery
  fragments remain on disk. Recovery support is retained internally.
- The Integrations button beside Settings opens only Voxray integration settings
  inside the existing menu-bar panel, with the same material and scrolling.
  It does not activate a separate application window or change Spaces. Back or
  Escape returns to the main menu; reopening the panel starts at the main menu.
  Integration settings stay available during capture.
- Each integration has its own labeled block. Voxray displays the installed CLI
  version in parentheses; unavailable version discovery does not block capture.
- Voxray call name, profile, Transcript and Keep video remain editable during
  capture and freeze together when Stop is accepted. Keep video defaults off:
  video captures file canonical audio, with an additional video copy in the call
  folder only when checked. Recorder originals are always retained.
  Keep video and its explanation appear only in Screen + Audio mode, including
  during capture. Audio mode has no video retention control. Switching modes
  updates menu layout without animating the entire panel or sliding its blocks.
  Transcript and Keep video share one row when both labels fit; otherwise they
  stack vertically without truncating their labels.
  With no destination selected, the name and processing checkboxes are disabled
  and a local-only explanation is shown. Selecting a profile re-enables them
  without clearing their values. Destination selection remains available. The Integrations page has no recording
  history, per-recording action buttons, or recording list. Unassigned recordings stay in BBC's configured
  output folder and never start Voxray processing automatically.
  The profile can be selected,
  changed or cleared before and during either audio-only or screen/video capture.
  Stop freezes the selected profile before shutdown; changes for a later capture
  cannot redirect queued recordings. An unassigned capture stays local unless
  explicitly processed later. Unavailable integration
  allows unassigned recording. Native XPC handoff happens only after the finalized
  file is synchronized; transcription never controls capture or deletes originals.
  Saved recording and ready transcript remain separate persisted states, with
  retry support retained internally.
  A per-recording Transcript checkbox selects whether the assigned recording
  is only filed as audio or also transcribed. It is enabled by default for
  compatibility, editable before/during capture, and frozen alongside the
  profile at Stop. Profiles do not enable transcription themselves.
  See [capture integration](../docs/VOXRAY_INTEGRATION.md).
- Real-time audio writer backpressure uses a bounded FIFO. Overflow or a flush
  timeout fails explicitly instead of silently producing a recording with gaps.
- Explicit content exclusion and local-only recording storage.
- No tracking or analytics.

## Automation

- `betterbettercapture://toggle` stops an active recording; otherwise it opens
  content selection before recording.
- `betterbettercapture://open-recordings` opens the output folder in Finder.
- Changes to these URLs are public compatibility changes and require README,
  tests where practical, and changelog updates.

## Interaction boundaries

- Settings → Shortcuts includes a configurable global Toggle Window shortcut
  that opens or closes the main menu-bar panel, including before its first manual
  opening after launch. It has no default key combination and does not change
  recording state.
- Escape dismisses the main menu-bar panel, whether opened by clicking the
  menu-bar icon or by the Toggle Window shortcut, without stopping a recording.
  Opening through the shortcut makes the existing panel key so keyboard commands
  work immediately. Repeating the shortcut toggles the panel using the same
  status button; closing with Escape preserves that toggle behavior.
- The main menu-bar panel shows the installed marketing version as a quiet
  footer; the full version and build identifier remain available in Settings.
- After capture shutdown and recovery checkpointing, Start Recording is available
  while previous recordings finalize. Each queued recording shows its filename,
  progress and elapsed time. Waiting time is shown for queued jobs; processing
  elapsed time starts when that job begins. Progress belongs to its job and
  cannot change a newer capture's state.
- After Stop is accepted, the disabled Stop action remains visible while capture
  shutdown completes. Recording toggles do nothing during shutdown. Quit is
  disabled during capture/shutdown and available during background processing;
  unfinished originals and recovery audio remain if the app exits.
  Audio processing runs away from the main actor and throttles progress delivery
  so long recordings cannot starve menu-bar interaction.
- Prefer native macOS and SwiftUI interaction patterns.
- Permission, capture, and save state must remain visible and truthful.
- Avoid adding remote services or background infrastructure to local recording
  behavior without an explicit product decision.

## Visual identity

- The product mark combines an open screen bracket, a tall shared divider, and
  two descending sound bars in one continuous visual system.
- The application icon uses the white mark on a teal rounded square.
- The menu-bar item uses the same geometry as a monochrome template image so it
  remains legible across macOS appearances and highlighted states.
- During either screen-and-audio or audio-only recording, the menu-bar item uses
  the shared red sine-wave recording mark instead of mode-specific camera or
  microphone symbols.
- Recording-state artwork uses transparent 18×18 and 36×36 template renditions,
  matching the idle menu-bar asset sizes so state changes cannot resize the
  macOS status item or introduce an artwork background.
