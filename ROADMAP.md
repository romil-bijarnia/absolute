# Development sequence

## Direction, 15 October 2026

The ultimate goal of Absolute is an open-source macOS clone: a free
Fedora-based system on which anything can be done and which looks and behaves
like macOS as closely as possible. Behavior is cloned; Apple code, fonts,
icons, sounds and names are not. Resemblance is built on the installed
Plasma/KWin session and real Fedora applications, with Absolute components
where no upstream piece matches the observed behavior.

Asahi's M3 feature table on 2026-10-15 lists the M3 Max GPU as TBA, the display
controller as WIP and brightness as WIP; the main display runs on the boot
framebuffer with software rendering. Daily use on this Mac waits on that driver
work, which this project cannot close. Development continues so the result is
ready when the driver lands or on other supported hardware.

Work proceeds one behavior at a time. Each unit observes the behavior on the
reference Mac, records a specification with an executable check, and implements
it for Plasma/KWin or as an Absolute component. System-wide inventories and
research sweeps are not units of work. The first unit is Dock magnification;
its evidence lives under `research/local/dock-magnification/`.

## Foundation: Fedora, Asahi and macOS compatibility

Build Absolute by combining existing open-source infrastructure with macOS
reverse engineering. Prefer integrating maintained upstream components before
writing new implementations. Keep investigation of the full system, including
firmware, in scope; an open research question is not automatically a requirement
to replace the corresponding component.

| Layer | Planned foundation | Absolute's work |
| --- | --- | --- |
| General operating system | The existing Fedora installation, kernel, packages and system services | Integrate Absolute into the physical Mac's desktop session and daily workflow |
| Apple Silicon hardware | Asahi boot tooling, kernel support, drivers and graphics work where available | Integrate matching upstream versions, verify the target Mac and address specific gaps |
| macOS experience and application interfaces | Observations and reverse engineering of the reference Mac, plus suitable open-source components | Implement and verify desktop behavior, framework/API compatibility and application execution |

[Fedora Asahi Remix](https://asahilinux.org/fedora/) combines Fedora with Asahi's
Apple Silicon work. Asahi also documents the components needed by other systems
in its [distribution guidelines](https://asahilinux.org/docs/alt/policy/).
Keep upstream component licenses and provenance with reused code and packages.

The development Mac reports Apple M3 Max, model `Mac15,10`. On 2026-10-14,
Asahi's [M3 support table](https://asahilinux.org/docs/platform/feature-support/m3/)
lists M3 Max GPU support as TBA and DCP support as WIP; boot-framebuffer output
is listed for the corresponding MacBook Pro family. Recheck those entries
when checking the installed system's actual hardware behavior. The user has
explicitly rejected a VM deliverable; the target is this physical Mac.

## Existing physical installation

On 2026-10-14, read-only inspection found Fedora Linux with KDE Plasma APFS
boot volumes, a 524.3 MB Fedora EFI partition, a 1.1 GB ext-family BOOT
partition and a 518.6 GB Btrfs partition on the internal disk. Fedora boot
files include m1n1, GRUB and kernel `7.1.6-400.asahi.fc44.aarch64+16k`.
These observations establish installation artifacts; boot success, the running
Fedora release and hardware health still need verification inside that system.

Use this installation as the base. Inspect its Plasma/KWin session, packages
and hardware support before choosing integration changes. The intended result
is the user's macOS replacement running directly on the laptop.

## Completed: Desktop previews 0.1 and 0.2

Build the development host on the existing Mac. Keep desktop state, directory
navigation, file metadata, search ranking, and previews in `AbsoluteCore`.
Use the native host to iterate on actual interactions and collect screenshots.

The initial component is Files plus the Dock and app launcher. REA provides
artifact and dependency evidence from the installed system; our interface and
core behavior are implemented independently in this project.

Preview 0.2 adds the file-service boundary, reveal-and-select, a read-only file
inspector, and versioned desktop-session persistence. The session includes every
file window's folder, hidden-file setting, sort order, view mode, geometry,
minimization, and wallpaper. Native checks exercise the user flows and restart
the application to check the saved state.

The same core and command-line host have compiled and run on Ubuntu ARM64.
All 12 core tests and seven integration checks passed on macOS and Linux.
See [research/PORTABILITY.md](research/PORTABILITY.md).

## Behavior specifications

The full requested research scope, including graphics and firmware, is tracked
in [research/SYSTEM-COVERAGE.md](research/SYSTEM-COVERAGE.md) and
[research/scope.json](research/scope.json). Every subsystem remains open.
Initial inventories now support targeted native-code and runtime investigations.
The first resulting compatibility change preserves symbolic-link traversal
through file services, CLI paths, navigation and saved sessions.
A subsequent `AbsoluteMach` component implements a measured in-process inline
message subset and matches an independent native oracle on macOS and Linux.
Cross-process transport, broader rights transfer and binary trapping remain
open; see [research/MACH-COMPATIBILITY.md](research/MACH-COMPATIBILITY.md).

For each component, choose a bounded question, observe it, and write an
interaction contract with an executable check. Begin with Dock activation,
minimize/restore, keyboard launcher selection, folder navigation, and sorting.
Preserve OS build and artifact hashes with each research run.

Source code, static metadata, and runtime behavior answer different questions.
The findings ledger identifies which type of evidence supports each statement.

## Completed: Linux graphical host 0.3

The Linux host renders a native GTK 4 desktop and Files windows using the same
file services, navigation, search ranking, and versioned session model.
GIO supplies installed applications and native launch operations.

All 27 graphical integration checks passed: real folder navigation, search,
hidden files, views, information, reveal, text previews, dragging, resizing,
minimize/restore, launcher selection, wallpaper, and a full process restart.
See [research/LINUX-DESKTOP.md](research/LINUX-DESKTOP.md).

The development VM exposes its virtual display through a local browser viewer.
Window management currently covers the desktop's own Files windows.

## Next: Native Fedora edition on this Mac

Verify the existing Fedora installation while booted on the physical Mac:
release and kernel, Plasma/KWin session, display rendering, input, networking,
audio, storage and power behavior. Package and install Absolute's components
into that environment, reusing its compositor, file manager, settings,
notifications, applications, installation and update facilities.

Validate the resulting desktop, real application windows and saved sessions
through native use and a restart. This is the delivery path for replacing
macOS in daily use. Preserve the existing boot/recovery layout during development;
partition removal is not a prerequisite for implementing the replacement.

Reuse Asahi's installed boot path and supported hardware components, and Linux
process, memory, storage and networking facilities. Continue macOS reverse
engineering for compatible loading, runtimes, frameworks and operating-system
interfaces, with each addition checked against the reference Mac.
