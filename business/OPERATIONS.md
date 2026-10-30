# Repository operations

## Fork boundaries

- `origin` is `RoTorEx/BetterBetterCapture` and is the default push target.
- `upstream` is `jsattler/BetterCapture` and is read-only unless the user
  explicitly asks for an upstream contribution.
- Preserve upstream history and keep fork changes small and reviewable.

## Local commands

- `make install` installs the required local lint tool.
- `make build`, `make test`, `make lint`, and `make check` are the stable local
  interfaces.
- `make install-local` builds and verifies a Release app with a persistent local
  self-signed identity, replaces `~/Applications/BetterBetterCapture.app`,
  registers and opens the installed app, and removes the disposable Debug app.
  It requires no Apple account or payment. Quit recording before installing.
- `scripts/local-signing.py` owns local signing setup. Its dedicated keychain,
  password file and public certificate live under
  `~/Library/Application Support/BetterBetterCapture/Signing/` with private
  directory/file permissions. The private key is imported as non-extractable;
  temporary PEM and PKCS#12 copies are removed after setup. The keychain is added
  to the user's existing search list without replacing other entries, and its
  certificate is trusted only for code signing in the user domain.
- Reuse this signing directory across builds and back it up securely with the
  machine. Never commit, upload, regenerate or remove it as build cleanup.
  Missing or invalid credentials stop installation rather than silently changing
  identity. The self-signed certificate lasts 3650 days (about ten years) to
  avoid routine identity rotation; expiry or replacement requires a deliberate
  signing migration and fresh user permissions. Signing is unlocked for each
  install and locks again on sleep or after one hour.
- The first transition from an ad-hoc or other signing identity requires one
  fresh permission grant. If Settings shows an enabled entry but macOS logs a
  code-requirement mismatch, quit the app and reset only the affected services
  for `com.betterbettercapture.app` with `tccutil reset ScreenCapture` and, when
  affected, `tccutil reset AudioCapture` or `tccutil reset Microphone` (append the
  bundle ID to each command). Reopen, grant permission, and Quit & Reopen when
  prompted. Never reset unrelated applications or permissions on every install.
  A plist or LaunchAgent cannot transfer a grant between signing identities.
- When changing local signing, verify two builds with different code-directory
  hashes: their designated requirements must match, and the new installed app
  must retain Screen Recording and Microphone authorization without another
  reset or grant. A successful `codesign --verify` alone does not prove TCC
  authorization. Read the app's permission checks and corresponding macOS TCC
  decisions after replacement.
- `make vibe-pull` refreshes committed kernel instructions without rewriting
  project-owned rules or commands.
- `make vibe-propose` is the only child-to-parent rule-feedback path.

## Release and publishing

- Follow `.vibe/kernel/RELEASE.md` for release preparation and tag push.
- Release versions follow the upstream calendar-year release line, not the
  current day: `YEAR.LINE.PATCH`. `LINE` advances with the upstream release
  train and `PATCH` advances for fixes on that line. For example, the August
  2026 upstream pre-release is `2026.4`, so the middle component is not a month.
- `make release` prompts for an exact `MAJOR.MINOR.PATCH`, verifies the project,
  updates Xcode marketing versions and `CHANGELOG.md`, creates the release commit,
  and adds an annotated tag. It does not push or publish.
- `make release-push` pushes `main` and tags to `origin` only.
- The signed/notarized DMG workflow is triggered only when a GitHub Release is
  explicitly published for the prepared tag. Publishing is a separate external
  mutation and requires explicit user approval and post-publish verification.
- Pre-release workflow behavior remains project-specific and is not implied by
  the normal stable release commands.

## Git

- Use conventional commits with concise imperative subjects.
- When explicitly working from a GitHub issue, the existing
  `gh issue develop <issue-number> --checkout` workflow may be used.
- Keep one completed coherent change per commit and push the tracked branch when
  ready unless the user says not to.
