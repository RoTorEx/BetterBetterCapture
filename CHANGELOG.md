# Changelog

## [Unreleased]

- Operations: adopted Vibecoding Kernel 1.3.3, routed product and engineering
  rules into focused modules, added stable local verification/release commands,
  and moved Xcode build state under `~/construction_side/better-better-capture`.
- Release metadata: normalized the Xcode marketing version to `2026.3.0`, the
  semantic-version equivalent of the latest stable `v2026.3` release line.
- CI: stopped masking Xcode build/test failures and captured the pre-existing
  SwiftLint debt in a baseline so new violations fail verification immediately.
