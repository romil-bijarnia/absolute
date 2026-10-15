# Absolute

[Current handoff](HANDOFF.md) · [Research coverage](research/SYSTEM-COVERAGE.md)

An open-source operating-system project with native macOS and Linux desktop
prototypes and a shared Swift core. The goal is macOS compatibility, with
research spanning applications, system services, graphics, boot and firmware.

The intended system combines Fedora's operating-system base, Asahi's Apple
Silicon support, and Absolute's desktop and macOS-compatible implementations
informed by reverse engineering. Reuse upstream components wherever they meet
the required behavior. The delivery target is the existing Fedora/Asahi
installation on the user's physical Mac, developed into a daily macOS replacement.
The Ubuntu VM preview below records earlier development work; it is not the
requested deliverable. See [ROADMAP.md](ROADMAP.md).

Since 15 October 2026 work proceeds in behavior units. The first two,
[Dock magnification](research/DOCK-MAGNIFICATION.md) and the
[minimise effects](research/DOCK-MINIMISE.md), are recovered from the installed
Dock and implemented as `DockMagnification` and `DockMinimise` in `AbsoluteCore`,
each with a browser demo under `research/`.
[System research and current coverage](research/SYSTEM-COVERAGE.md) records
what has been inspected, what has been implemented, and what remains open.
Current deliverables are the Fedora surface installer (built and checked in a
Fedora 44 virtual machine on the Mac), the two measured Dock behaviors with
their demos, desktop prototypes, verified file-service behavior and
reproducible system research.

## Native Fedora edition

The existing Fedora Asahi KDE system is the deployment target. From a terminal
in a Fedora KDE Plasma 6 session, physical or in the project's virtual machine:

```sh
bash script/absolute_surface.sh --all
```

That installs the packages, fetches WhiteSur at pinned commits, renders the
wallpaper, applies the Absolute Plasma profile after backing up the current
preferences, sets the window, font, search, notification and shortcut
behaviour, and themes the login screen. The result is the macOS-like surface:
menu bar with the active application's menus, floating Dock with the Fedora
applications in their Mac roles, traffic-light window decorations, Inter,
Magic Lamp minimise, Overview, centred search on Meta+Space. See
[linux/fedora/README.md](linux/fedora/README.md) for each step, the restore
command and the virtual machine (`script/vm_fedora.sh`) used to build it.

`script/install_fedora.sh --install` additionally builds the optional Swift/GTK
preview on the physical installation; its `--apply-desktop` delegates to the
surface installer.

## Development previews

Desktop Preview 0.3 includes:

- A desktop with three procedural wallpapers and draggable, resizable windows.
- A Dock that opens Files, searches installed apps, launches pinned apps, and restores minimized windows.
- A file browser that reads real folders, with icon and list views, navigation history, sorting, hidden files, and folder search.
- An application launcher with ranked search, keyboard navigation, and native application launching.
- Text previews, revealing files in our own Files app, and a read-only Get Info panel on both platforms. The macOS host also supports image previews and copying paths.
- Saved desktop sessions: window positions, sizes, order, minimized state, folders, view preferences, and wallpaper.
- A native GTK 4 Linux desktop, with real mouse and keyboard interactions and session restoration.
- A command-line host that uses the same file and session services on macOS and Linux.
- File and session paths that preserve symbolic-link traversal, including dangling-link metadata and explicit follow/no-follow resolution.
- A portable inline Mach-message component checked against native macOS observations on both macOS and Linux.

## Run the macOS development preview

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

## Legacy Linux VM preview

The following Lima commands reproduce the earlier VM preview. Native Fedora
deployment on the physical Mac is the current development target.

On an Apple Silicon Mac with Lima installed:

```sh
./script/run_linux.sh
```

Open [the local desktop viewer](http://localhost:6090/vnc_lite.html?scale=true). The viewer
streams a real GTK desktop running inside the project-owned Ubuntu VM. Linux
renders the interface; noVNC carries its display and input to your browser.
The desktop scales to fit the browser window. Allow a few seconds after connecting
for the first desktop frame to appear.
The VM mounts this project and keeps build caches and desktop state in separate
container volumes.

```sh
./script/run_linux.sh --build-only
./script/run_linux.sh --self-check
./script/run_linux.sh --stop
```

The graphical self-check drives X11 mouse and keyboard events, then quits and
relaunches the desktop to check saved sessions. All 27 checks passed on the
tested Ubuntu 24.04 ARM64 / GTK 4.14.5 / Swift 6.2.4 configuration.
Reports and screenshots are generated under `research/local/`.
See [research/LINUX-DESKTOP.md](research/LINUX-DESKTOP.md) for the tested scope.
Stopping the desktop preserves its state. Stop the VM separately with
`limactl stop absolute-dev`.

On a Linux machine with Swift 6 and GTK 4.12 or newer development libraries:

```sh
swift run --package-path linux AbsoluteLinux --project "$PWD"
```

Linux shortcuts use **Ctrl** (or **Super**): **K** opens the launcher, **N** opens
Files, **I** shows file information, **[ / ]** navigate, **↑** opens the parent
folder, **Shift+.** shows hidden files, **Shift+D** changes the wallpaper, and
**Q** quits. **Space** previews a focused file; **Escape** closes an overlay.

## Run the shared command-line core

The command-line host has no AppKit or SwiftUI dependency:

```sh
swift run absolute ls .
swift run absolute info Package.swift
swift run absolute reveal Package.swift
swift run absolute mach-demo
./script/check_core.sh
```

On this Mac, reproduce the Linux run in the project-owned Lima VM:

```sh
./script/check_linux.sh
```

The script starts an Ubuntu 24.04 ARM64 VM and runs a pinned Swift 6.2 container,
with a separate Linux build cache. The suites run 44 unit tests on macOS and
43 on Linux, plus 16 CLI integration checks on each; the extra Mac test checks
the native SDK header layout. The VM uses two CPUs, 4 GB of memory,
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

That script covers the initial Dock/Finder bundle inspection. The broader
research now includes system inventory, native function analysis, firmware
containers and monitor startup, shared-cache images, kernel interfaces and
owned-process graphics/kernel probes. See the
[coverage index](research/SYSTEM-COVERAGE.md) for evidence and limitations.

On the reference Mac, individual investigations can be reproduced with:

```sh
python3 script/inventory_macos.py
python3 script/research_kernel_abi.py
python3 script/research_boot_firmware.py --rea
python3 script/research_boot_monitors.py
python3 script/research_graphics.py --probe
python3 script/research_shared_cache.py
python3 script/research_native_code.py
python3 script/research_dock_magnification.py
python3 script/research_dock_minimise.py
python3 script/research_status.py
```

These workflows use Python, the installed macOS developer tools, and the
project-local REA runtime. Native decompilation also requires Ghidra and a
compatible Java installation. Full raw captures remain local. Passing a
bounded probe does not establish complete macOS or firmware compatibility.

## Structure

```text
Sources/AbsoluteCore/            File services, navigation, search ranking, saved desktop state, text previews
Sources/AbsoluteDesktop/         macOS development host, native views, platform services
Sources/AbsoluteCLI/             Shared command-line host for macOS and Linux
linux/Sources/AbsoluteLinux/     Native Linux host using the shared core
linux/Sources/DesktopToolkit/    GTK and GIO bridge for Linux rendering and services
linux/container/                Pinned Linux development image and display startup
Tests/AbsoluteCoreTests/         Behavior tests for the portable core
script/                         Reproducible build, run, test, and REA workflows
research/                       Findings ledger and local evidence
tools/                          Project-local research dependencies
```

`AbsoluteCore` imports Foundation and has no AppKit or SwiftUI dependency. The
separate `AbsoluteMach` module implements a measured inline-message subset in
one process; see [its contract and conformance results](research/MACH-COMPATIBILITY.md). The
macOS host owns its application discovery, icons, launching, clipboard access,
and window rendering. The separate Linux package supplies GTK rendering and
GIO application discovery and launching without introducing GTK dependencies
into the core.

Both hosts currently run desktop applications on an existing operating system.
The Linux host manages its own Files windows; external application windows
still need a compositor and complete session integration. A standalone system
also needs system services, boot integration, and hardware support. Native Mac
application compatibility is a separate implementation effort.

The next slice is native integration with the existing Fedora KDE/Asahi system
on the physical Mac, including application windows and session behavior.
See [ROADMAP.md](ROADMAP.md).

Original project code is available under the MIT license.
