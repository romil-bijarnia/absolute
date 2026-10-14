# Absolute handoff

This checkpoint is saved on the main branch of
[romil-bijarnia/absolute](https://github.com/romil-bijarnia/absolute).
The local checkout is `/Users/romilbijarnia/absolute`.

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
[http://localhost:6090/vnc_lite.html](http://localhost:6090/vnc_lite.html).
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

Static firmware analysis does not supply Boot ROM, decrypted SEP code or a
working physical-Mac boot path. All subsystem scopes remain open.

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

1. Package a self-contained bootable VM image with its desktop and dependencies.
2. Add a compositor and session lifecycle for external application windows.
3. Expand the measured Mach contract into a cross-process transport and broader
   rights/message handling, keeping each addition tied to native observations.
4. Continue the kernel trap, driver and graphics protocols listed in the
   coverage backlog. Inventories and isolated probes do not close those scopes.

Read [AGENTS.md](AGENTS.md) before changing code. Preserve the user’s preference
for direct action, concise updates, and no authorship acknowledgements.
