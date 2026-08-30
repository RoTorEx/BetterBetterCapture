# Changelog

## [Unreleased]

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
