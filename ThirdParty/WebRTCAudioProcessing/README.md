# WebRTC Audio Processing

The checked-in static library is built from
[`webrtc-audio-processing` v2.1](https://gitlab.freedesktop.org/pulseaudio/webrtc-audio-processing/-/tree/v2.1),
commit `846fe90a289f58b7c9303a635142aa2c7caa93e5`, with its Meson-pinned Abseil
fallback (`20240722.0`). It is used through the small C API in
`include/WebRTCAudioProcessing.h`.

Run `scripts/build-webrtc-audio-processing.sh` to reproduce the arm64 macOS
archive. The script builds outside the repository and replaces only
`lib/libWebRTCAudioProcessing.a`.

Upstream is BSD-3-Clause licensed and includes an additional patent grant; see
`LICENSE` and `PATENTS`.
