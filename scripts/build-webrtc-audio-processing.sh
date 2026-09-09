#!/bin/zsh
set -euo pipefail

readonly revision="846fe90a289f58b7c9303a635142aa2c7caa93e5"
readonly root="${0:A:h:h}"
readonly work="$(mktemp -d)"
trap 'rm -rf -- "$work"' EXIT

for tool in git meson ninja clang++ libtool strip; do
    command -v "$tool" >/dev/null || { print -u2 "Missing build tool: $tool"; exit 1; }
done

git clone --filter=blob:none https://gitlab.freedesktop.org/pulseaudio/webrtc-audio-processing.git "$work/source"
git -C "$work/source" checkout --detach "$revision"
MACOSX_DEPLOYMENT_TARGET=15.2 meson setup "$work/source/build" "$work/source" \
    --default-library=static --buildtype=release
MACOSX_DEPLOYMENT_TARGET=15.2 meson compile -C "$work/source/build"

MACOSX_DEPLOYMENT_TARGET=15.2 clang++ -std=c++17 -O2 -DNDEBUG -DWEBRTC_MAC -DWEBRTC_POSIX \
    -I"$root/ThirdParty/WebRTCAudioProcessing/include" \
    -I"$work/source" -I"$work/source/webrtc" \
    -I"$work/source/subprojects/abseil-cpp-20240722.0" \
    -I"$work/source/subprojects/abseil-cpp-20240722.0" \
    -c "$root/ThirdParty/WebRTCAudioProcessing/WebRTCAudioProcessingBridge.cc" \
    -o "$work/bridge.o"

mkdir -p "$root/ThirdParty/WebRTCAudioProcessing/lib"
libtool -static -o "$root/ThirdParty/WebRTCAudioProcessing/lib/libWebRTCAudioProcessing.a" \
    "$work/bridge.o" \
    "$work/source/build/webrtc/modules/audio_processing/libwebrtc-audio-processing-2.a" \
    "$work/source/build/subprojects/abseil-cpp-20240722.0/"libabsl_*.a
strip -S "$root/ThirdParty/WebRTCAudioProcessing/lib/libWebRTCAudioProcessing.a"
