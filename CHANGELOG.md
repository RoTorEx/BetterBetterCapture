# Changelog

## [Unreleased]

- Menu-bar recording status now uses the shared sine-wave icon for both video
  and audio-only recordings.

## [2026.3.4] - 2026-09-12

- Fixed a race where hundreds of thousands of queued audio-progress updates
  could starve the main UI and leave the menu-bar panel permanently busy after
  a recording had saved. Audio finalization now runs on a concurrent executor
  and publishes at most about one hundred ordered progress updates.
- Recording toggles are now ignored during stopping and processing, the Stop
  action remains visible while shutdown is underway, and Quit is disabled while
  a recording is active or being finalized.

## [2026.3.3] - 2026-09-10

- Menu-bar panel: keep the primary recording button visible but disabled while
  audio is processing, and reserve the end of the progress bar for file
  finalization so it no longer appears stuck at 100%.

## [2026.3.2] - 2026-09-09

- Menu-bar panel: added a quiet footer showing the installed app version.

## [2026.3.1] - 2026-09-09

- Audio: replaced the noise-amplifying 0.75-second Auto gain calibration with
  default WebRTC voice processing (AEC3, noise suppression, AGC2), a Raw mode
  for fixed gain, lossless intermediates, one final encode, a -1 dBFS limiter,
  processing progress, and recoverable failed finalization.
- Audio-only capture: added a 2x2, 1 fps discard screen consumer to prevent the
  ScreenCaptureKit missing-output error loop.

- Menu-bar panel: Escape now explicitly dismisses the panel without affecting
  an active recording.
- Shortcuts: added a configurable global Toggle Window action to show or hide
  the menu-bar panel, with shortcut registration available from launch.
- Visual identity: adopted the selected screen-and-sound mark for both the teal
  application icon and the adaptive monochrome menu-bar icon.
- Local installation: added `make install-local` to install a verified,
  Apple Development-signed Release build in `~/Applications`, preserving macOS
  privacy permissions while removing the confusing Spotlight-visible Debug
  product.
- Build hygiene: moved Xcode DerivedData into a `.noindex` directory so local
  debug app bundles do not appear in Spotlight.
- App icon: replaced the legacy concentric-circle artwork with the film-reel
  mark used in the menu bar.
- Operations: adopted Vibecoding Kernel 1.3.3, routed product and engineering
  rules into focused modules, added stable local verification/release commands,
  and moved Xcode build state under `~/construction_side/better-better-capture`.
- Release metadata: normalized the Xcode marketing version to `2026.3.0`, the
  semantic-version equivalent of the latest stable `v2026.3` release line.
- CI: stopped masking Xcode build/test failures and captured the pre-existing
  SwiftLint debt in a baseline so new violations fail verification immediately.
- Tests: isolated recorder settings so repeated verification cannot leak
  persisted audio-only state between test cases or runs.
