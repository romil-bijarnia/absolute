# Local macOS desktop evidence

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
