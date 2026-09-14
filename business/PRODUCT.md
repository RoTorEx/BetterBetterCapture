# Product contract

## Scope

- Native menu-bar screen recording for macOS 15.2 or later.
- ProRes 422/4444, HEVC/H.265, and H.264 encoding, including supported alpha and
  HDR workflows.
- Simultaneous system-audio and microphone capture.
- Voice microphone processing is the default: system audio is used as the
  far-end reference for WebRTC AEC3, followed by noise suppression and AGC2.
  Raw mode bypasses voice processing and permits a fixed gain.
- Capture audio is held in a lossless intermediate and encoded once at stop.
  Final output contains one mixed audio track; video is remuxed without a
  second encode. A failed processing pass preserves an `unprocessed.mov` file.
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
- The main menu-bar panel shows the installed marketing version as a quiet
  footer; the full version and build identifier remain available in Settings.
- While audio is being finalized, the main menu-bar panel keeps Start Recording
  visible but disabled and shows truthful progress. The action becomes available
  again only after the output file is ready. Final progress delivery is ordered
  before the return to idle so a late update cannot leave the panel permanently busy.
- After Stop is accepted, the disabled Stop action remains visible while capture
  shutdown completes. Recording toggles do nothing during shutdown or audio
  processing, and Quit is disabled until the local output is safely finalized.
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
