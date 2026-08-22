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
- `make vibe-pull` refreshes committed kernel instructions without rewriting
  project-owned rules or commands.
- `make vibe-propose` is the only child-to-parent rule-feedback path.

## Release and publishing

- Follow `.vibe/kernel/RELEASE.md` for release preparation and tag push.
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
