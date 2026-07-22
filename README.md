# New The Unarchiver for macOS

A native macOS app that brings the legendary The Unarchiver experience back to
the community: drop an archive, get your files. Built with SwiftUI on top of
the cross-platform **New The Unarchiver** Rust engine.

> **Status: pre-alpha.** v1 feature set is complete; distribution (signing,
> notarization, DMG) is still ahead.

## What it does

- Extracts archives — never creates them. Drag & drop, double-click,
  Finder "Open With", or `File ▸ Open…`.
- Parallel extraction queue with per-job progress, password prompts, and
  filename-encoding override.
- Quick Look extension: press Space on an archive to preview its contents.
- Preferences: file-format associations, destination and enclosing-folder
  rules, post-extraction actions.

All archive logic (format detection, decompression, passwords, encodings,
path safety) lives in the [newtua-core](https://github.com/new-the-unarchiver/newtua-core)
engine, which ships prebuilt via the
[newtua-swift](https://github.com/new-the-unarchiver/newtua-swift) package —
no Rust toolchain is needed to build the app.

## Requirements

- macOS 26+ (Apple Silicon)
- Xcode to build; the `Newtua` Swift package is fetched by SwiftPM —
  no other dependencies

## Building

Open `NewTheUnarchiver/NewTheUnarchiver.xcodeproj` in Xcode and build the
`NewTheUnarchiver` scheme. There is no notarized distribution yet.

## Repository layout

| Path | Purpose |
|------|---------|
| `NewTheUnarchiver/` | Xcode project, sources, tests, working docs |
| `docs/history/` | Historical planning and analysis documents |

Part of the [new-the-unarchiver](https://github.com/new-the-unarchiver)
organization.
