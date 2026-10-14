# Linux desktop verification

This records the initial Preview 0.3 graphical milestone. Current regression
results are recorded in [SYSTEM-COVERAGE.md](SYSTEM-COVERAGE.md).

Desktop Preview 0.3 implements a native GTK 4 Linux host for `AbsoluteCore`.
It compiled with Swift 6.2.4 and ran on Ubuntu 24.04 ARM64 with GTK 4.14.5
inside the project-owned Lima VM.

## Reproduce

```sh
./script/run_linux.sh --self-check
./script/run_linux.sh
```

The run command prints a local noVNC viewer URL. The test runs in its own
container and uses an isolated state file. Full reports and Linux screenshots
are generated under gitignored `research/local/`; they are not bundled with
the repository.

The verified run on 2026-10-14 is recorded locally in
`research/local/linux-ui-check-20261014-063403/results.json`.
All 27 checks passed, with no reported errors.

## Verified behavior

- A real GTK window reads a real folder and discovers installed Linux apps.
- X11 mouse and keyboard input navigates folders, filters entries, goes back
  and forward, shows hidden files, and switches to list view.
- Get Info reads metadata through the shared file service. Reveal selects the
  file in its containing folder. Space opens a shared-core text preview.
- Dragging and resizing update shared window geometry. Minimize and Dock
  restore retain the same window. Multiple Files windows keep separate state.
- The launcher supports mouse selection, arrow selection, ranked search,
  and Escape dismissal. The desktop can change wallpapers.
- Normal quit exits and flushes state. A fresh process restores window order,
  geometry, minimization, folders, preferences, and wallpaper without folder
  errors.

The five captured views show the desktop, file information, application
launcher, pre-quit desktop, and restored desktop. External application
launches are implemented through GIO but were not exercised by this test.

## Implementation boundary

`AbsoluteCore` remains free of GTK, AppKit, and SwiftUI. The separate `linux/`
Swift package supplies a C bridge for GTK widgets, input, icons, application
discovery, and GIO launch operations. Swift owns the shared desktop session
and file browser state.

Presentation changes stay on the GLib event loop. Saves use immutable snapshots
and the existing state repository, debounce by 250 milliseconds, and flush on
normal quit or termination. Files windows use the existing version 1 session
schema. The macOS-specific About window is omitted by the Linux host.

The development container uses Xvfb for a Linux display, x11vnc, and noVNC.
The viewer is forwarded to localhost on the Mac. Separate container volumes
hold Linux build products and saved sessions; source is mounted from this
project. The Swift base image is pinned by digest in
`linux/container/Containerfile`.

## Remaining work

This is a Linux desktop application in a development VM. It manages its own
Files windows and does not yet provide an external-window compositor, login
session, or self-contained bootable image. File browsing is read-only.

The successful checks establish this project's behavior on Linux. They do
not establish macOS binary compatibility or complete macOS reverse engineering.
The current REA findings cover initial static Dock and Finder inspection.
