# Development sequence

## Direction, 15 October 2026

The ultimate goal of Absolute is an open-source macOS clone: a free
Fedora-based system on which anything can be done and which looks and behaves
like macOS as closely as possible. Behavior is cloned; Apple code, fonts,
icons, sounds and names are not. The motive, in Romil's words: using an
assistant on macOS "runs into many different blocks"; the point is a system
with no TCC prompts, sealed volumes, notarisation or unpatchable system apps,
where automation and root are unrestricted. The Fedora base supplies that on
day one; the resemblance is the long tail. Resemblance is built on the installed
Plasma/KWin session and real Fedora applications, with Absolute components
where no upstream piece matches the observed behavior.

Asahi's M3 feature table on 2026-10-15 lists the M3 Max GPU as TBA, the display
controller as WIP and brightness as WIP; the main display runs on the boot
framebuffer with software rendering. Daily use on this Mac waits on that driver
work, which this project cannot close. Development continues so the result is
ready when the driver lands or on other supported hardware.

Evening of 15 October 2026, after the second unit: the whole surface comes
first, then the behaviors. Romil wanted to open Fedora and see macOS, not one
effect at a time, so `script/absolute_surface.sh` now turns a Fedora KDE
session into the complete look in one run (menu bar with global menus,
floating Dock, WhiteSur decorations, icons and cursors, Inter, the night
wallpaper, Magic Lamp, Overview, centred search, Mac-style shortcuts, Konsole
profile, login screen). It was built and checked inside a Fedora 44 virtual
machine on the Mac (`script/vm_fedora.sh`), which is the development rig, not
the deliverable; the same installer runs unchanged on the physical Fedora
Asahi installation. The Fedora boot partition's `grubenv` carries
`boot_success=1` written on 14 October 2026 04:35 on a Fedora Asahi Remix 44
install (kernel 7.1.6-400.asahi), so this Mac has booted Fedora into a user
session at least once; the GPU remains software rendered until Asahi's M3
driver lands. The measured behaviors (magnification, minimise) are layered on
top of this surface next.

Work proceeds one behavior at a time. Each unit observes the behavior on the
reference Mac, records a specification with an executable check, and implements
it for Plasma/KWin or as an Absolute component. System-wide inventories and
research sweeps are not units of work. The first unit, Dock magnification, is
complete ([research/DOCK-MAGNIFICATION.md](research/DOCK-MAGNIFICATION.md)),
and so is the second, the three minimise effects (Genie, Scale and the hidden
Suck) with their clock and the tile's arrival reveal
([research/DOCK-MINIMISE.md](research/DOCK-MINIMISE.md)); the raw evidence for
both lives under `research/local/dock-magnification/`. Next on the Dock: the
GTK host and the KWin effect that render these two models on Fedora, then
bounce, indicators and autohide timing.

## Behavior backlog, 15 October 2026

Romil's stated scope is everything: every part of macOS reproduced, down to
settings, the password manager and the firmware. Each line below is a unit or
a group of units, in the order that makes the clone usable soonest. A unit is
done when it has a report under `research/`, an executable check and an
implementation on Plasma/KWin or in Absolute.

| Order | Target | Units | State |
| --- | --- | --- | --- |
| 1 | Dock | Magnification geometry and ramp; minimise effects (Genie, Scale, Suck); bounce, indicators, autohide timing; GTK host and KWin wiring | Magnification and minimise effects done; hosts open |
| 2 | Input physics | Trackpad acceleration (IOHIDFamily is published source), scroll momentum and rubber-banding, gesture thresholds | Open |
| 3 | Window management | Traffic lights, shadows, zoom and minimise animations, Mission Control, Spaces, app switcher, menu bar model | Open |
| 4 | Finder | Views, sidebar, Quick Look, Get Info, drag semantics, file operations | Partial (Files prototype, link semantics) |
| 5 | System Settings | Pane by pane: layout, controls and behavior, each wired to the Fedora setting underneath | Open |
| 6 | Passwords | List, groups, verification codes, autofill prompts and sheets; local store on Fedora, sync by the user's choice | Open; iCloud Keychain sync is Apple-server-bound and stays out |
| 7 | Text and appearance | CoreText-like rendering (unhinted, subpixel-positioned), materials, dark/light appearance, SF-metric open typeface | Open |
| 8 | Spotlight, Notification Centre, Control Centre | Search ranking and layout; notification grouping and timing; control panels | Open |
| 9 | Firmware | M3 display-controller (DCP) and GPU (AGX) command protocols traced from macOS under the m1n1 hypervisor, Asahi's method, feeding driver work upstream; SEP and Boot ROM are signed and stay Apple's | Open; this is the item that unblocks daily use on this Mac |

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
