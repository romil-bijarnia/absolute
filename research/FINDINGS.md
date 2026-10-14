# Local macOS desktop evidence

This report covers the initial Dock/Finder bundle pass. See [SYSTEM-COVERAGE.md](SYSTEM-COVERAGE.md) for the current system-wide investigation.

REA 6.4.0; macOS 27.0, build 26A5421a.
The targets were `/System/Library/CoreServices/Dock.app` and `/System/Library/CoreServices/Finder.app`.
All eight static inspections completed. No target process was launched or modified.

## Observations

| Measured fact | Dock | Finder |
| --- | --- | --- |
| Bundle identifier | com.apple.dock | com.apple.finder |
| Bundle version | 2571.0.6.402 | 1865 |
| Regular-file path occurrences | 416 | 3250 |
| Executable roots | 5 | 8 |
| Main-executable bytes | 4843616 | 13116272 |
| Main-executable architecture | arm64e | arm64e |
| Declared main-executable dylib loads | 83 | 125 |

`Dock.app/Contents/Info.plist` declares `LSUIElement = true`. Dock includes DockControls.appex and three XPC-service executables: DockHelper, com.apple.dock.external.extra.arm64, and com.apple.dock.extra.

`Finder.app/Contents/Info.plist` declares the services `open`, `reveal`, and `showInfo`; the principal class is `TApplication` and the main nib is `Application`. Its bundle also contains FileSearch.appex and the AirDrop, All My Files, Computer, Network, Recents, and iCloud Drive executable roots. These declarations and names do not establish runtime behavior.

Both main executables declare loads of SkyLight, DesktopServicesPriv, and IconServices. Dock also declares WindowManager, WindowManagement, and RunningBoardServices. Finder declares AppKit, SwiftUI, FileProvider, CoreSpotlight, and QuickLookUI. Exact paths and all executable SHA-256 identities are retained in [findings.json](findings.json).

Across their executable roots, Dock has 161 declared load edges and Finder has 166. Every one has resolution status `undetermined`: the candidates lie outside the selected bundles. This is a search boundary, not a finding that libraries are missing. System libraries may be supplied by the dyld shared cache.

## Evidence ledger

| Target | Operation | Canonical Evidence ID |
| --- | --- | --- |
| Dock | inspect_artifact | `ev_4fbbc1a7fb113472fbb46aeef1882bcd80b3e3dd463ae57f10833e6968da9aff` |
| Dock | inspect_plist | `ev_2439a1d1e895e0b6acd725b1571a37bff7b2d8f485891532189358f4b6e98181` |
| Dock | inspect_macho | `ev_9d0aba5ef7556f54148145fb56878c95919dfb87abe8068439f374a2fd730f82` |
| Dock | trace_dylib_resolution | `ev_ec40c3ad104ea2208883775dfccacd60df9d78da4ff8b675577be670c561a49f` |
| Finder | inspect_artifact | `ev_777aa96eba4c4062620b7bd6b3c1e118fb088f7629b5a96ff2de23cedda369e2` |
| Finder | inspect_plist | `ev_31c54504362348f15aa441089a325a6ea845f7430983bbd974e73fe6df6940f8` |
| Finder | inspect_macho | `ev_785ae250d2782d74de905a10105921055080912e463b217c8960f41608de6913` |
| Finder | trace_dylib_resolution | `ev_fc28f1e16f5df310e4e9d9f8917713b6838fd739fde2a1ce33cd377501a1fa01` |

The complete unfiltered CLI JSON records and a capture manifest with output hashes live in `research/local/`, which is ignored by Git.
Initial failed plist/Mach-O envelopes are retained there as `*.failed-*.json`; they were cleanup failures caused by a sandbox-blocked process-table read and are not successful native observations. The successful retry records above are the evidence used here.

## Reconstruction implication

**Inference:** The desktop depends on services outside the two app bundles. Rebuilding their observable behavior requires separate replacements for those service boundaries.

**Next component, design choice:** a file-service boundary for our Files app, using Finder’s declared `open`, `reveal`, and `showInfo` messages as investigation seeds. A reviewable first specification is: open a selected folder in the file browser; reveal a file by navigating to its parent and selecting it; show a read-only inspector with name, type, size, and modification time. Verify those results against a known temporary folder and metadata from the filesystem. Before claiming Finder compatibility, separately observe its actual inputs and outputs. Keep filesystem operations behind an interface so the desktop can later use another operating-system backend.

**Answered:** exact bundle inventory, main-executable identity and architecture, parsed application declarations, and bounded dylib load declarations. **Unresolved:** process behavior, visual metrics, window-server behavior, private-service protocols, kernel, drivers, and boot sequence. No pseudocode or original source was recovered in this pass.

## Reproduce

From the project root after installing the pinned tools:

```sh
tools/node_modules/node/bin/node script/research_macos.mjs
```

By default the script reuses complete records captured on the same macOS build. Add `--refresh` to inspect again; earlier records are preserved. It also writes `findings.json` and this ledger from retained canonical Evidence. All target inspections are static.

## Physical Fedora installation

Read-only inspection on 2026-10-14 found an existing Fedora installation on the
internal physical disk of the Apple M3 Max / Mac15,10 reference laptop. Its BLS
boot entry identifies **Fedora Linux Asahi Remix 44, KDE Plasma Desktop Edition**,
with kernel `7.1.6-400.asahi.fc44.aarch64+16k` and a Btrfs `root` subvolume.

The Fedora EFI partition contains m1n1 v1.6.1, an embedded U-Boot 2026.07
payload, shim and GRUB. The separate ext-family BOOT partition contains the
matching kernel, initramfs, configuration and Apple device trees. GRUB's saved
entry matches the installed kernel and stores `boot_success=1`; this is
historical metadata, not a new boot test or proof of current hardware health.

The sanitized local record is
`research/local/physical-fedora-boot-20261014.json`, SHA-256
`01314a69f2952e5626dbf876f97025a8c3a92a4b4508d33407afe6ba4216615f`.
This observation is separate from the earlier macOS inventory counts.

The implementation target is this physical Fedora/Asahi installation, developed
into the user's macOS replacement. The user explicitly rejected a VM deliverable.
Native boot, running release, session integration and hardware behavior remain
to be checked from within Fedora before deployment readiness is claimed.

## Native Fedora system packages

On 2026-10-14, `script/research_fedora_installation.py` opened the physical Btrfs
partition read-only using Dissect's Btrfs parser. It inspected selected system
files and queried an in-memory copy of the installed RPM database. All 2,249
package headers matched their name index, SQLite's quick check passed, and the
database WAL was empty. These are static records, not executions of Fedora code.

`/usr/lib/os-release` identifies Fedora Linux Asahi Remix 44, KDE Plasma Desktop
Edition. Selected installed versions are:

| Component | Version |
| --- | --- |
| Plasma, KWin and Plasma Login Manager | 6.7.4 |
| Qt | 6.11.2 |
| GTK / GLib | 4.22.4 / 2.88.3 |
| Mesa | 26.1.8 |
| Dolphin / Konsole | 26.08.0 |
| Firefox | 155.0 |

The configured display manager is `plasmalogin.service`; the installed Plasma
session is Wayland. Fedora and Breeze appearance packages are present.
The system RPM records and checked system paths lack Swift, Clang, GCC, and
GTK/GLib development files. A toolchain at an uninspected location is not ruled out.

The local evidence is `research/local/fedora-installation-findings.json`,
identity `absolute-fedora-installation-2617fbd241f6d8acadeb`, SHA-256
`d220545aba51f9f013a2b6d022b475eece3859da8875f2dc04182386a6ca909b`.
It contains selected package versions, upstream license labels, system defaults
and application IDs. User homes, private keys and personal documents were outside
the inspection scope.

These findings support integrating Absolute with the existing Plasma/KWin
session and installed applications. They do not establish active desktop settings,
rendering performance or working hardware, which require native runtime checks.
