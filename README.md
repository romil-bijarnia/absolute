# Absolute

A desktop developed on macOS, with a shared Swift core now running on macOS
and Linux, and an incremental path toward a bootable open-source system.

Desktop Preview 0.2 includes:

- A desktop with three procedural wallpapers and draggable, resizable windows.
- A Dock that opens Files, searches installed apps, launches pinned apps, and restores minimized windows.
- A file browser that reads real folders, with icon and list views, navigation history, sorting, hidden files, and folder search.
- An application launcher with ranked search, keyboard navigation, and native application launching.
- Text and image previews, copying paths, revealing files in our own Files app, and a read-only Get Info panel.
- Saved desktop sessions: window positions, sizes, order, minimized state, folders, view preferences, and wallpaper.
- A command-line host that uses the same file and session services on macOS and Linux.

## Run on your Mac

Requires macOS 14 or newer and a Swift 6 toolchain. The application has no remote
Swift package dependencies.

```sh
./script/build_and_run.sh
```

This builds and stages `dist/Absolute.app`, then opens it. You can also open that
app bundle directly. The project includes a Codex Run action.

Useful commands:

```sh
./script/build_and_run.sh --build-only
./script/build_and_run.sh --test
./script/build_and_run.sh --self-check --background
```

The self-check exercises native file navigation, reveal, Get Info, window state,
and keyboard commands, then quits and launches a fresh process to verify session
restoration. It uses an isolated state file and saves screenshots and JSON reports
under `research/local/`. Both test processes quit automatically. `--background`
keeps launch activation off; omit it when you want to watch the checks.
Background mode checks the Get Info shortcut's registration and exercises its
action directly, since macOS focus-dependent commands need an active scene.

Keyboard shortcuts: **⌘K** searches applications, **⌘N** opens another file
window, **⌘[ / ⌘]** navigate back and forward, **⌘↑** opens the parent folder,
**⌘R** refreshes, **⌘I** shows file information, **⌘⇧.** shows hidden files, and **Space** previews a selected
file. Escape closes the launcher. Application launching uses the current
macOS host.

Sessions save automatically to
`~/Library/Application Support/Absolute/desktop-session.json` and flush on normal
quit. Invalid or unsupported saved state is preserved instead of overwritten;
its error appears in the Absolute menu. On Linux the default state location is
`$XDG_STATE_HOME/absolute/desktop-session.json`, falling back to
`~/.local/state/absolute/desktop-session.json`.

## Run the shared core on Linux

The command-line host has no AppKit or SwiftUI dependency:

```sh
swift run absolute ls .
swift run absolute info Package.swift
swift run absolute reveal Package.swift
./script/check_core.sh
```

On this Mac, reproduce the Linux run in the project-owned Lima VM:

```sh
./script/check_linux.sh
```

The script starts an Ubuntu 24.04 ARM64 VM and runs a pinned Swift 6.2 container,
with a separate Linux build cache. It runs the same 12 core tests and seven
integration checks as the macOS core host. The VM uses two CPUs, 4 GB of memory,
and a 16 GB disk; its writable host mount is this project. Stop it when done with
`limactl stop absolute-dev`. See [research/PORTABILITY.md](research/PORTABILITY.md)
for the recorded results and tested boundaries.

## Research the installed system with REA

REA 6.4.0 and a supported Node 24 runtime are isolated in `tools/`.

```sh
npm install --prefix tools --omit=optional
./tools/node_modules/node/bin/node script/research_macos.mjs
```

The research script inspects the installed Dock and Finder bundles without
changing them. Complete local evidence lives under `research/local/`; a concise
ledger links observations to their evidence in [research/FINDINGS.md](research/FINDINGS.md).
Reruns reuse successful records. The tool version, target identities, scope,
and errors are retained so later investigations can build on this pass.

## Structure

```text
Sources/AbsoluteCore/            File services, navigation, search ranking, saved desktop state, text previews
Sources/AbsoluteDesktop/         macOS development host, native views, platform services
Sources/AbsoluteCLI/             Shared command-line host for macOS and Linux
Tests/AbsoluteCoreTests/         Behavior tests for the portable core
script/                         Reproducible build, run, test, and REA workflows
research/                       Findings ledger and local evidence
tools/                          Project-local research dependencies
```

`AbsoluteCore` imports Foundation and has no AppKit or SwiftUI dependency. The
macOS host owns application discovery, icons, launching, clipboard access, and
window rendering. That boundary is deliberate: moving the core to another
system requires a new platform adapter and renderer.

This version is a desktop application running on macOS. A standalone system
still needs an open-source display/compositor backend, system services, boot
integration, and drivers. Native Mac application compatibility is a later,
separate implementation effort.

The next slice is a Linux graphical host for the verified core, followed by
packaging a desktop session into a bootable VM image. See [ROADMAP.md](ROADMAP.md).

Original project code is available under the MIT license.
