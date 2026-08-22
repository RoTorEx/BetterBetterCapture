# Business

This file routes durable product truth for BetterBetterCapture. Read only the
focused module needed for the current task.

## Purpose

BetterBetterCapture is a free, native macOS screen recorder focused on local,
private recording with professional video and audio formats and a lightweight
menu-bar experience.

## Actors

- The recorder user selects content, starts and stops captures, and owns the
  resulting local files.
- macOS provides ScreenCaptureKit, permissions, audio/video devices, encoding,
  and application lifecycle behavior.
- External automation tools may invoke the documented custom URL scheme.
- GitHub distributes source and release artifacts; the upstream repository is a
  separate project boundary.

## Core concepts

- A capture selects display/window/area content plus optional system and
  microphone audio, then writes an encoded local recording.
- Content filtering excludes explicitly selected content from the capture.
- `betterbettercapture://` is the public automation scheme for supported local
  actions.
- `origin` is this fork; `upstream` is the original BetterCapture repository.

## Business flows

- Select content, configure capture, record, stop, and save locally.
- Open the recordings folder without mutating capture settings.
- Prepare a local release commit/tag, push it separately, then explicitly
  publish a GitHub Release to trigger signed/notarized artifact creation.

## Invariants

- Recordings remain local; the app has no tracking or analytics.
- External URL actions expose only documented capture/folder operations.
- Capture, permission, and encoding failures must not silently claim success.
- New third-party frameworks require explicit user approval.
- Fork-specific changes are pushed only to `origin`, never implicitly upstream.

## Decisions and numbers

| Value | Unit | Meaning | Rationale/source | Change impact | Protecting tests |
|---|---|---|---|---|---|
| 15.2 | macOS version | Minimum supported operating system | Current product requirement and project deployment target | Changes availability and API assumptions | Xcode build settings and platform availability checks |
| 6.2+ | Swift toolchain | Intended modern compiler/toolchain generation | Established engineering direction | Changes compiler/API availability | `make check` on the supported Xcode toolchain |
| 200 | characters | SwiftLint line-length error threshold | Existing lint policy balances media-code readability | Changes CI acceptance | `make lint` |
| 800 | lines/file | SwiftLint file-length error threshold | Existing upper safety bound | Changes refactoring pressure | `make lint` |

## Module map

| Code area | Business source | Why to read it |
|---|---|---|
| Recording, settings, automation, UI behavior | `business/PRODUCT.md` | Product capabilities, privacy, and public behavior |
| Swift source, tests, Xcode project | `business/ENGINEERING.md` | Language, concurrency, UI, persistence, and verification boundaries |
| GitHub workflows, website, versioning | `business/OPERATIONS.md` | Fork ownership, release publishing, and repository commands |

## Non-goals

- Hosted recording, analytics, tracking, or cloud ownership of recordings.
- Speculative frameworks, abstractions, or compatibility work not required by a
  current feature.
