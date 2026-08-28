# Engineering contract

## Toolchain

- Target macOS 15.2 or later.
- Use Xcode with a Swift 6.2-or-later compiler and modern Swift concurrency.
- The existing Xcode project currently uses Swift 5 language mode. Do not switch
  language mode or enable stricter concurrency as a side effect; treat that as a
  dedicated migration with its own fixes and verification.
- Do not introduce third-party frameworks without explicit user approval.
- Avoid AppKit/UIKit unless the requested macOS behavior requires it.

## Swift

- Mark shared `@Observable` reference types `@MainActor`.
- Prefer Swift-native and modern Foundation APIs.
- Use structured concurrency instead of new Grand Central Dispatch flows.
- Use localized, user-appropriate matching such as
  `localizedStandardContains()` for user-entered search text.
- Avoid force unwraps and force `try` unless failure is genuinely unrecoverable.
- Use Swift formatting APIs instead of C-style number formatting.

## SwiftUI

- Prefer `foregroundStyle()`, `clipShape(.rect(cornerRadius:))`, `Tab`,
  `NavigationStack`, and `navigationDestination(for:)` over deprecated forms.
- Prefer `@Observable`; do not introduce `ObservableObject` for new shared state.
- Use `Button` for actions; reserve gestures for gesture-specific behavior.
- Use `Task.sleep(for:)`, Dynamic Type, and modern layout APIs.
- Extract substantial views into separate `View` types and keep testable logic
  outside view bodies.
- Avoid `AnyView`, hard-coded sizing/spacing, and framework-specific colors
  unless the design requires them.

## SwiftData

When a model uses CloudKit:

- do not use `@Attribute(.unique)`;
- give properties defaults or make them optional;
- make relationships optional.

## Structure and verification

- Organize source by feature and keep distinct types in distinct Swift files.
- Add unit tests for core logic; use UI tests only when unit coverage cannot
  verify the behavior.
- `make check` is the required read-only local gate. It runs SwiftLint and the
  Xcode test suite without hiding failures.
- `.swiftlint-baseline.json` records only violations that predate kernel
  adoption. Do not add new violations to the baseline as routine maintenance;
  remove entries when the underlying code is repaired.
- Put Xcode DerivedData under
  `~/construction_side/better-better-capture/DerivedData.noindex` so debug app
  bundles do not appear in Spotlight. Keep cloned package state under
  `~/construction_side/better-better-capture/`, never in the repository.
- Put task-local temporary artifacts under the same construction-side directory
  and remove them when the task or command finishes.
- Never commit secrets, signing material, provisioning profiles, or API keys.
