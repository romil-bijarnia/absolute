# macOS system inventory

Reference: macOS 27.0, build 26A5421a, captured on 2026-10-14.
The [inventory script](../script/inventory_macos.py) walks twelve explicit
system roots, records symlinks without traversing them, recognizes structured
Mach-O headers, and parses bundle and launchd declarations.

| Observation | Count | Meaning |
| --- | ---: | --- |
| Regular file paths | 334,215 | Path occurrences, including resources and templates |
| All recorded paths | 525,909 | Files, directories and symlinks |
| Symbolic links | 16,438 | Targets recorded; directory links not followed |
| Mach-O files | 5,458 | Recognized thin or universal containers |
| Bundle paths | 6,692 | Roles inferred from bundle suffixes |
| Framework paths | 3,010 | Includes nested and repeated packaging paths |
| Application paths | 333 | Includes nested system applications |
| XPC-service paths | 475 | Packaging declarations, not observed processes |
| Kernel-extension paths | 843 | Packaging declarations, not loaded-driver count |
| Driver-extension paths | 22 | Packaging declarations |
| Driver personalities | 2,532 | Static IOKit match declarations |
| Launchd jobs | 902 | Parsed system agent and daemon plists |
| Mach-service declarations | 2,054 | Names declared by those jobs |

The selected roots are `/System/Applications`, `/System/Library`,
`/System/DriverKit`, `/Library/Apple/System/Library`, `/usr/bin`, `/usr/sbin`,
`/usr/lib`, `/usr/libexec`, `/usr/share`, `/usr/standalone`, `/bin` and `/sbin`.

There were **90 read denials**: 65 directory scans and 25 file-header reads.
Many are template spool directories and restricted helper files. These are
retained as gaps. No permission change was made to complete the inventory.
Malformed XML accepted by Apple's plist tool is normalized through `plutil`
on stdout for parsing; source files are not rewritten.

The native slice counts are 5,311 arm64e, 97 arm64, 4,272 x86_64 and 229
with CPU type `0x01000013`. Universal files contribute multiple slices.
The last group declares Mach-O GPU-executable type; this pass does not establish
its instruction-set semantics.

This filesystem pass does not count every image inside shared caches, kernel
collections or firmware containers. Those have separate evidence in
[SHARED-CACHE.md](SHARED-CACHE.md) and [BOOT-FIRMWARE.md](BOOT-FIRMWARE.md).
Counts across these reports must not be added as a unique-component total.

The full path, binary, bundle, launch-job and error records remain local:
`research/local/system-catalog/20261014T071026575174Z/`.
All retained record hashes, byte lengths, unique paths and manifest counts
were checked. The public projection is [system-inventory.json](system-inventory.json).

Evidence identity:
`absolute-inventory-sha256:a79254d0f1363940fd2fa3d3a7a0b1f40c517fc20ab4540ccec4fbfe55a095b0`.
This is an Absolute inventory identity, not a REA Evidence ID.

```sh
python3 script/inventory_macos.py
```

Each run creates a new capture. This inventory establishes what was readable
inside its roots. It does not establish code understanding, runtime activation,
protocol compatibility or whole-system reverse-engineering completion.
