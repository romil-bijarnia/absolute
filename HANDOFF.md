# Absolute handoff

This checkpoint is saved on the main branch of
[romil-bijarnia/absolute](https://github.com/romil-bijarnia/absolute).
The local checkout is `/Users/romilbijarnia/absolute`.

## Fedora surface, 15 October 2026 evening

Romil's instruction that evening: stop delivering one effect at a time and make
Fedora look like macOS as a whole first, then switch to that system and keep
building from inside it. `script/absolute_surface.sh` is that deliverable:
`--all` installs packages, fetches WhiteSur (KDE, icons, cursors, GTK) at the
commits pinned in `linux/fedora/plasma/profile.json`, renders the wallpaper
with `script/wallpaper_absolute.py`, applies the `org.absolute.desktop`
profile (menu bar, floating Dock, WhiteSur appearance, Inter and JetBrains
Mono) after a preferences backup, sets KWin (Magic Lamp, blur, Overview,
centred placement, no borders), the centred search, notifications top right,
the lock screen, the Konsole profile and the shortcuts through the shortcut
service, and sets up the login screen (Plasma Login Manager on Fedora 44:
wallpaper in `/etc/plasmalogin.conf`, theme assets copied for its greeter
user).

It was built and verified inside a Fedora 44 aarch64 virtual machine created
by `script/vm_fedora.sh` (Homebrew QEMU with the Hypervisor framework, cloud
image plus cloud-init, under `~/.local/share/absolute/vm`). Screenshots were
taken through QEMU's monitor after each change; the desktop, Dolphin, Konsole,
System Settings, the search, Overview, Launchpad and the login screen all
render as intended. Plasma there is 6.7.5, the same major release as the
physical Fedora Asahi 44 installation, whose boot partition records a
successful boot on 14 October 2026 (`grubenv` `boot_success=1`). Not yet done
on the physical Mac: running the installer there (it needs a Plasma session
on that machine), the Firefox WhiteSur tweak, Mac-style modifier remapping for
applications (Toshy or keyd), and the measured Dock behaviors on this surface.
Quirks learnt: Qt 6 font strings must use the sixteen-field form; Plasma 6.7
puts the first widget added to a fresh panel at its end (the layout script
settles the order); the shortcut service lives inside `kwin_wayland` and
rewrites `kglobalshortcutsrc`, so shortcuts are set over DBus; the login
manager ignores its `conf.d`.

## Implementation direction

Current direction (2026-10-15): the ultimate goal is an open-source macOS
clone, a free Fedora-based system that looks and behaves like macOS as closely
as possible, built one measured behavior at a time; see ROADMAP.md. The first
two behavior units are complete: Dock magnification
([research/DOCK-MAGNIFICATION.md](research/DOCK-MAGNIFICATION.md),
`Sources/AbsoluteCore/DockMagnification.swift`, 11 tests) and the minimise
effects ([research/DOCK-MINIMISE.md](research/DOCK-MINIMISE.md),
`Sources/AbsoluteCore/DockMinimise.swift`, 15 tests), each with a browser demo
under `research/`. The next Dock unit renders both models on Fedora: the GTK
host's pointer handling for magnification and a KWin effect for minimising. Asahi lists the M3 Max GPU as TBA and the
display controller as WIP, so daily use on this Mac waits on upstream driver
work. The full behavior backlog, including System Settings, Passwords and the
M3 DCP/AGX firmware protocols, is the table in ROADMAP.md. The paragraphs
below describe the earlier framing.

Combine Fedora/Asahi with macOS reverse engineering. Fedora supplies the
planned operating-system base; Asahi supplies reusable Apple Silicon boot,
driver and graphics work where supported. Absolute supplies desktop behavior
and macOS compatibility above those components. Prefer upstream integration
before writing replacements, and preserve the full firmware research scope.

The target is the existing Fedora/Asahi installation on the physical Mac,
developed into the user's macOS replacement. A VM is not the deliverable; the Fedora 44
machine from `script/vm_fedora.sh` is the rig the surface is built and checked
in, and the Ubuntu VM below is historical development infrastructure.
Read [ROADMAP.md](ROADMAP.md) for the model-specific support boundary. The
research backlog records unresolved behavior and integration as well as new
implementation; it is not a list of components that must all be written afresh.

Read-only inspection on 2026-10-14 found Fedora Linux with KDE Plasma boot
volumes and Fedora EFI, ext-family BOOT and Btrfs partitions on the internal
disk. The physical boot entry identifies Fedora Linux Asahi Remix 44, KDE
Plasma Desktop Edition, with kernel `7.1.6-400.asahi.fc44.aarch64+16k`.
Matching m1n1, U-Boot, GRUB, kernel and initramfs artifacts are present.
See [the installation observation](research/FINDINGS.md#physical-fedora-installation).
The installed Fedora session still needs
to be booted and inspected before claiming native Absolute or hardware readiness.
The accidentally started `absolute-fedora` VM was stopped and removed; its
unfinished configuration and desktop patch are archived under gitignored
`research/local/cancelled-fedora-vm-work/`.

Read-only Btrfs inspection also confirms Fedora Asahi 44 in `/usr/lib/os-release`
and installed Plasma/KWin 6.7.4, Qt 6.11.2, GTK 4.22.4, Mesa 26.1.8,
Dolphin/Konsole 26.08.0 and Firefox 155.0. The installed Plasma session uses
Wayland and `plasmalogin.service`. Swift and the required development packages
are absent from the system package database. The selected system evidence is
`research/local/fedora-installation-findings.json`; see
[FINDINGS.md](research/FINDINGS.md#native-fedora-system-packages).

Native delivery sources now include `script/install_fedora.sh`,
`script/check_fedora.sh` and `linux/fedora/plasma/`. They prepare a user-local
build/install and a backed-up Plasma profile using real Fedora applications.
`script/package_fedora.py` creates an explicitly allowlisted source archive.
Native installation, profile rendering and physical-hardware acceptance have
not run while macOS is the active operating system.

## Working software

- Native macOS desktop prototype: Files, Dock, launcher, floating windows,
  previews, file information, procedural wallpapers and saved sessions.
- Native GTK 4 Linux desktop prototype using the same Swift core. It runs in
  the project-owned Ubuntu ARM64 Lima VM and streams its display through noVNC.
- Shared filesystem behavior preserves dangling-link identity, symlink/parent
  traversal and trailing-slash directory requirements through CLI and state paths.
- `AbsoluteMach` implements the measured in-process inline-message subset.
  It includes a user-header codec, local port namespace, FIFO queues, reference
  accounting, timeout/error behavior and default receive trailers.

The Linux preview is available locally at
[http://localhost:6090/vnc_lite.html?scale=true](http://localhost:6090/vnc_lite.html?scale=true).
The VM is named `absolute-dev`; its desktop container is `absolute-desktop`.
Browsing is read-only in the desktop UI. External application launching is
implemented, but it is not covered by the graphical test suites.

## Verification at this checkpoint

| Check | macOS | Linux |
| --- | ---: | ---: |
| Unit tests | 44 | 43 |
| CLI integration checks | 16 | 16 |
| Desktop and restart checks | 33 | 27 |

The extra Mac unit test compares the Mach codec against the installed SDK's
native C structure. Both hosts replay all 23 independently captured Mach
scenarios with two different name assignments. The native oracle contains
211 checks and 386 recorded operations; two native runs agree exactly.

Source hashes and report identities are in
[implementation-verification.json](research/implementation-verification.json)
and [mach-compatibility.json](research/mach-compatibility.json).

## Research completed

[SYSTEM-COVERAGE.md](research/SYSTEM-COVERAGE.md) is the main index;
[scope.json](research/scope.json) records open questions across 19 subsystems.

- Inventoried 334,215 regular-file paths and 5,458 Mach-O file paths across
  twelve selected system roots. Ninety read denials are retained as gaps.
- Verified 4,083 active shared-cache image headers and mapped 89,379 declared
  dependency edges. This is metadata coverage, not recovered implementations.
- Inspected 180 boot/firmware artifact records, decoded the model-specific
  device tree and kernel collections, and analyzed selected SPTM/TXM startup code.
- Obtained 11 canonical REA function dossiers, plus focused IOSurface and
  libsystem_kernel assembly analysis. A subsequent kernel send pass inspects
  six function-start spans; it does not resolve the full user trap path.
- Captured 26 owned-process kernel checks, five headless graphics probes,
  73 filesystem utility cases, and the independent Mach-message reference.

Full evidence, extracted binaries and disassembly remain under gitignored
`research/local/` on this Mac. GitHub contains original project code, normalized
fixtures, hashes, reports and explicit limitations. A fresh clone will not have
the local raw captures; investigation scripts document how to reproduce them.

## Important limits

This is a desktop prototype and a collection of verified compatibility pieces.
There is no self-contained bootable Absolute image, full compositor/session,
Mac application binary support, replacement kernel, Apple GPU driver, or
replacement firmware. The Linux preview uses an existing Ubuntu VM.

`AbsoluteMach` is an in-process namespace. It does not provide cross-process
Mach IPC, descriptors, vouchers, reply rights, blocking waits or trap handling.
The native C oracle remains independent of that implementation.

Static firmware analysis does not supply Boot ROM or decrypted SEP code.
The existing physical Fedora boot artifacts are separate from Absolute;
native deployment and boot verification of Absolute remain open.

## Commands

```sh
./script/build_and_run.sh
./script/run_linux.sh
./script/check_core.sh
./script/check_linux.sh
./script/build_and_run.sh --self-check --background
./script/run_linux.sh --self-check
swift run absolute mach-demo
python3 script/research_status.py --check
```

To stop the preview and release VM resources:

```sh
./script/run_linux.sh --stop
limactl stop absolute-dev
```

The desktop keeps its saved state in the `absolute-linux-state` container
volume. Tests use isolated state. The project is the VM's writable Mac mount.

## Next implementation boundaries

1. Boot the physical Fedora Asahi installation, clone the repository there and
   run `bash script/absolute_surface.sh --all`; compare with the VM screenshots.
2. Put the measured Dock behaviors on this surface (GTK host pointer handling
   for magnification, a KWin effect for the minimise meshes), then Mac-style
   modifier remapping and the Passwords migration (KeePassXC).
3. Expand the measured Mach contract into a cross-process transport and broader
   rights/message handling, keeping each addition tied to native observations.
4. Map required kernel and service behavior onto the Linux base, integrate Asahi
   hardware support where available, and investigate the remaining compatibility
   gaps. Inventories and isolated probes do not close those scopes.

Read [AGENTS.md](AGENTS.md) before changing code. Preserve the user’s preference
for direct action, concise updates, and no authorship acknowledgements.
