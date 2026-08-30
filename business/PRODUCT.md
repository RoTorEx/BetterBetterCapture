# Product contract

## Scope

- Native menu-bar screen recording for macOS 15.2 or later.
- ProRes 422/4444, HEVC/H.265, and H.264 encoding, including supported alpha and
  HDR workflows.
- Simultaneous system-audio and microphone capture.
- Explicit content exclusion and local-only recording storage.
- No tracking or analytics.

## Automation

- `betterbettercapture://toggle` stops an active recording; otherwise it opens
  content selection before recording.
- `betterbettercapture://open-recordings` opens the output folder in Finder.
- Changes to these URLs are public compatibility changes and require README,
  tests where practical, and changelog updates.

## Interaction boundaries

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
