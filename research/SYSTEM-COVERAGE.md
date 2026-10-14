# System research coverage

**Overall status: in progress. Full macOS reverse engineering is incomplete.**

The requested scope includes graphics, boot and firmware. The current
reference is macOS 27.0, build 26A5421a.
This index is generated from the linked reports and their hashed JSON records.

## Implementation approach

Target the existing Fedora KDE/Asahi installation on the physical Mac. The user explicitly rejected a VM deliverable. Reuse its operating-system foundation, session services and supported Apple Silicon components, and implement Absolute's desktop and macOS-compatible interfaces above them.

The subsystem backlog includes research, compatibility and integration gaps. Open items do not automatically require rewriting the kernel, drivers, firmware or services. Reused components count toward a stated contract only after integration and verification on the intended target.

See [ROADMAP.md](../ROADMAP.md) for the Fedora/Asahi integration sequence
and the current physical-hardware support boundary.

## Native Fedora package

Version 0.4.0-dev is prepared for the existing physical Fedora installation.
Its [installer and Plasma profile](../linux/fedora/README.md) have structural,
backup/restore and source-archive checks recorded in
[fedora-native-verification.json](fedora-native-verification.json).

Status: **native-validation-pending**. Native compilation, profile activation,
rendered desktop behavior and hardware acceptance have not been verified
from the current macOS session. These checks are separate from the older
macOS and Ubuntu preview results below.

## Measured work

| Measurement | Count |
| --- | ---: |
| Regular file paths inventoried | 334,215 |
| Mach-O file paths identified | 5,458 |
| Shared-cache image headers verified | 4,083 |
| Shared-cache dependency declarations | 89,379 |
| Launchd job declarations | 902 |
| Mach-service declarations | 2,054 |
| Firmware/boot artifact records | 180 |
| Canonical REA function dossiers | 11 |
| Selected IOSurface/libsystem_kernel functions inspected | 23 |
| Filesystem runtime cases captured | 73 |
| Owned-process kernel reference checks passed | 26 |
| Headless graphics reference probes passed | 5 |
| Mach-message reference scenarios | 23 |
| Mach-message native checks passed | 211 |
| Recorded Mach operations replayed per pass | 386 |
| Selected kernel-send function-start spans inspected | 6 |
| Behavior units specified, implemented and tested | 1 |

These counts measure different kinds of work and overlap. They do not form
a completion percentage. File names, export names and dependency edges do
not establish recovered behavior. Native-code dossiers retain unresolved
flows, inferred types and provider limitations described in their reports.

The filesystem capture also records 90 read denials.
Shared-cache and firmware captures have separate boundaries and identities.

## What changed in Absolute

The file service now preserves dangling-link identity and separates
literal link destinations from successful target resolution. Symbolic-link
traversal survives CLI parsing, navigation, snapshots and session-state paths.
See [NATIVE-CODE.md](NATIVE-CODE.md) for the observed contract and remaining limits.

The separate AbsoluteMach component now implements the measured in-process
inline-message subset. Its tests replay the independent native reference
with two name assignments on both hosts, comparing returned bytes, rights,
queue state, timeouts and trailers. See
[MACH-COMPATIBILITY.md](MACH-COMPATIBILITY.md).

The first behavior unit is Dock magnification: the fish geometry and ramp
timing recovered from the installed Dock are implemented as
`DockMagnification` in AbsoluteCore, with 5 Dock procedures
decompiled and the two measured constants decoded from the binary. See
[DOCK-MAGNIFICATION.md](DOCK-MAGNIFICATION.md).

| Verification | macOS | Linux |
| --- | ---: | ---: |
| Unit tests | 55 | 43 |
| CLI integration checks | 16 | 16 |
| Desktop and restart checks | 33 | 27 |

The [verification record](implementation-verification.json) binds these
results to source hashes and retained local reports. The GTK host still
runs in a development VM; it is not a self-contained bootable OS image.

## Subsystems still open

| Subsystem | Current depth | Evidence | Next unresolved boundary |
| --- | --- | --- | --- |
| Boot chain and monitor startup | Partial investigation | [BOOT-FIRMWARE](BOOT-FIRMWARE.md), [BOOT-MONITORS](BOOT-MONITORS.md) | Boot ROM and LLB implementation |
| Device firmware and coprocessors | Partial investigation | [BOOT-FIRMWARE](BOOT-FIRMWARE.md) | AGX/DCP command protocols and firmware logic |
| Kernel memory, IPC and synchronization | Partial investigation | [MACH-COMPATIBILITY](MACH-COMPATIBILITY.md), [MACH-MESSAGES](MACH-MESSAGES.md), [MACH-KERNEL](MACH-KERNEL.md), [KERNEL-ABI](KERNEL-ABI.md), [SHARED-CACHE](SHARED-CACHE.md) | Cross-process Mach transport and rights/descriptor transfer |
| Window server, drawing and GPU | Partial investigation | [GRAPHICS](GRAPHICS.md) | WindowServer and compositor internals |
| File paths and link semantics | Partial investigation | [NATIVE-CODE](NATIVE-CODE.md) | Races and concurrent filesystem mutation |
| Filesystems and storage | Inventory only | [SYSTEM-INVENTORY](SYSTEM-INVENTORY.md), [BOOT-FIRMWARE](BOOT-FIRMWARE.md) | APFS structures and operations |
| Drivers and I/O | Inventory only | [SYSTEM-INVENTORY](SYSTEM-INVENTORY.md), [BOOT-FIRMWARE](BOOT-FIRMWARE.md) | IOKit/DriverKit object and message contracts |
| Binary loading and language runtimes | Partial investigation | [KERNEL-ABI](KERNEL-ABI.md), [SHARED-CACHE](SHARED-CACHE.md) | Mach-O loading and dyld fixups |
| Local services and IPC protocols | Inventory only | [SYSTEM-INVENTORY](SYSTEM-INVENTORY.md), [SHARED-CACHE](SHARED-CACHE.md) | Launchd scheduling and lifecycle semantics |
| Networking and discovery | Inventory only | [SYSTEM-INVENTORY](SYSTEM-INVENTORY.md), [SHARED-CACHE](SHARED-CACHE.md) | Sockets and packet behavior |
| Security and identity | Inventory only | [SYSTEM-INVENTORY](SYSTEM-INVENTORY.md), [BOOT-FIRMWARE](BOOT-FIRMWARE.md) | Keychain and authentication behavior |
| Audio, video and imaging | Inventory only | [SYSTEM-INVENTORY](SYSTEM-INVENTORY.md), [SHARED-CACHE](SHARED-CACHE.md) | CoreAudio graph, timing and device behavior |
| Input and accessibility | Inventory only | [SYSTEM-INVENTORY](SYSTEM-INVENTORY.md) | HID and event delivery |
| Desktop and applications | Partial investigation | [FINDINGS](FINDINGS.md), [NATIVE-CODE](NATIVE-CODE.md), [LINUX-DESKTOP](LINUX-DESKTOP.md), [DOCK-MAGNIFICATION](DOCK-MAGNIFICATION.md) | Finder and Dock behavior beyond current prototypes |
| Power and thermal management | Inventory only | [SYSTEM-INVENTORY](SYSTEM-INVENTORY.md), [BOOT-FIRMWARE](BOOT-FIRMWARE.md) | Sleep, wake and shutdown transitions |
| Installation, updates and recovery | Inventory only | [SYSTEM-INVENTORY](SYSTEM-INVENTORY.md), [BOOT-FIRMWARE](BOOT-FIRMWARE.md) | Installation and update state machines |
| Text, localization and printing | Inventory only | [SYSTEM-INVENTORY](SYSTEM-INVENTORY.md), [SHARED-CACHE](SHARED-CACHE.md) | Text shaping and font contracts |
| Cloud and continuity clients | Inventory only | [SYSTEM-INVENTORY](SYSTEM-INVENTORY.md), [SHARED-CACHE](SHARED-CACHE.md) | Local client behavior and synchronization contracts |
| Automation and development interfaces | Inventory only | [SYSTEM-INVENTORY](SYSTEM-INVENTORY.md), [SHARED-CACHE](SHARED-CACHE.md) | Apple Events and scripting behavior |

The full open-question list is in [scope.json](scope.json). A component
can be completed only for a stated target and contract after its behavior
is established, supplied by an integrated upstream component or implemented
in Absolute, and checked against the reference.
No subsystem is marked complete by this pass.

## Reproduce and extend

Investigation-specific commands appear in each report. Run
python3 script/research_status.py after updating the evidence and verification
record; add --check to verify that this index is current without changing it.
The generator checks report links, source hashes and recorded check results.

Complete captures, extracted code and decompiler output remain in the
Git-ignored research/local directory. Public reports preserve identities,
original explanations, test contracts and explicit gaps.
