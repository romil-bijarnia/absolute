# macOS graphics investigation

Captured on 14 October 2026: macOS 27.0, build 26A5421a, Apple M3 Max.
This pass analyzed two WindowServer bootstrap functions and twelve selected
IOSurface functions, inventoried eight graphics images from the dyld shared
cache, and ran five headless graphics probes. Graphics reverse engineering
remains partial. Absolute has no replacement Apple GPU driver or firmware.

Exact image identities, selected exports, load declarations, function addresses,
tool-output hashes and probe results are in [graphics-findings.json](graphics-findings.json).
Complete evidence stays under the Git-ignored `research/local/graphics/` directory.
No Apple binary, disassembly listing or decompiler output is published here.

## WindowServer bootstrap: recovered static behavior

The installed WindowServer executable is 93,824 bytes, arm64e, with SHA-256
`a5ec46a944529c91a92da14c64e1cf9dcfe0feda2a4580a307b961adbbdb31ac`.
Its load commands name SkyLight and libSystem. The entrypoint is `0x100000718`.

REA 6.4.0 with the installed Ghidra 12.1.3 analyzed these two non-thunk functions:

| Function | Body bytes | Static interpretation |
| --- | ---: | --- |
| Entry, `0x100000718` | 128 | Set effective group and user to 88; assert on failure; call the local setup helper; delegate to SkyLight's `SLXServer`. |
| Setup, `0x100000798` | 1,140 | Resolve the home directory, prepare WindowServer temporary/cache directories, enter the named `com.apple.WindowServer` sandbox with directory parameters, and exit with failure if setup fails. |

Their body sizes account for the bootstrap executable's 1,268-byte `__text`
section. The separate import stubs and SkyLight's server implementation are
outside that statement. No WindowServer process was launched or attached to;
these are interpretations of static code, not observations of its execution.

The installed launchd plist declares ten Mach service names, including
`com.apple.windowserver`, `com.apple.CARenderServer`,
`com.apple.CoreDisplay.master`, `com.apple.VirtualDisplay` and HID-related
services. It passes `-daemon` and names a `com.apple.backboardd.conclave`.
These declarations identify further boundaries; they do not reveal IPC message
formats or the behavior of those services.

| REA operation | Canonical Evidence ID |
| --- | --- |
| WindowServer Mach-O inspection | `ev_46bd65339db57527fdc64100f48d0a26736fb8f9b97ba17fa6992ac54acbc505` |
| Entry function analysis | `ev_381c395b2913ec1304e491e0d5d3ced7adae4dd75a2650fae497d8bc69b7d545` |
| Setup function analysis | `ev_8cc27a02040edbc46588468db1c4a331c2da4dc50b3ad349e400dcf9aabefd18` |
| Launchd plist inspection | `ev_8a09644361aa57ee921e8726b2b90652efb91954d7f135b926b17345827a1726` |

## Cached graphics images

The principal executable paths of these frameworks and the AGX Metal plug-in
are absent as ordinary files on this installation. Apple's installed
`dyld_info` reads them directly from the shared cache. The cache map and image
UUIDs identify the capture; absence of standalone files does not mean missing
implementations.

| Image | Export rows | Declared dylib loads |
| --- | ---: | ---: |
| SkyLight | 2,912 | 60 |
| CoreGraphics | 5,646 | 27 |
| QuartzCore | 2,079 | 31 |
| Metal | 1,479 | 19 |
| IOSurface | 610 | 6 |
| CoreDisplay | 531 | 19 |
| IOGPU | 375 | 12 |
| AGXMetalG15X_M1 | 56 | 14 |

The total is 13,688 exported symbol rows, including re-exports. Names and load
edges are static evidence; they are not 13,688 recovered functions or tested
APIs. Selected investigation seeds include `SLSNewWindow`, `SLSOrderWindow`,
`SLSSetWindowBounds`, `CALayer`, `CAMetalLayer`, `MTLCreateSystemDefaultDevice`,
`IOSurfaceCreate` and `IOGPUCommandQueueCreate`.

SkyLight declares dependencies on CoreGraphics, QuartzCore, CoreDisplay, Metal,
IOSurface, IOKit and IOMobileFramebuffer. CoreGraphics also declares a SkyLight
dependency. The selected AGX Metal plug-in loads IOGPU, Metal, IOSurface and
IOKit. These edges justify treating window composition, image surfaces,
application drawing and GPU submission as separate investigation areas.

## IOSurface implementation: getters and synchronization

Apple's `dyld_info` produced a 1,011,246-byte disassembly of the IOSurface image
only. Twelve selected named functions, totaling 193 displayed instructions,
were inspected. This is direct assembly analysis, separate from the REA
WindowServer results. The complete disassembly SHA-256 is
`919aea83f5bc15a275949bebdf1150ca3b47718e1a981f68362b773400e31e92`;
the image UUID is `E43F5077-2102-3B68-9814-CF7E5E527AAF`.

Observed code facts for this image:

- Public getters resolve the Objective-C object's `_impl` ivar before calling
  a client getter. The width client getter reads an eight-byte field at `+0x98`;
  allocation size reads eight bytes at `+0x90`; plane count reads four bytes at
  `+0xc8`. The public width and allocation-size wrappers return zero for a null
  object.
- The client row-stride getter inspects a byte in each plane record when the
  plane count is nonzero. A value of one in any inspected record selects a
  zero result; otherwise it reads the eight-byte row-stride field at `+0xa8`.
  The meaning of that plane-record flag has not been established.
- `IOSurfaceLock` and `IOSurfaceUnlock` resolve `_impl` and delegate to their
  client functions. Their null-object branches return `0xe00002c2`.
- Both client functions obtain a connection, read a surface identifier from
  `+0x88`, and call the same external routine. Lock passes selector 2; unlock
  passes selector 3. The other arguments contain the identifier, options and
  an output-seed pointer. On success they store the seed at `+0xd8` and copy it
  to the caller's optional seed pointer.

A bounded [linkage probe](../script/research_graphics_linkage.c) resolves the
external routine as `IOConnectTrap3`. It reads the call instruction and at most
six branch-stub instructions mapped into its own process, follows the observed
ADRP/ADD/LDR/BRAA sequence, and compares the branch destination with the
`IOConnectTrap3` address returned by `dlsym`. Both comparisons passed. It does
not execute either private client entrypoint, attach to another process, or
modify code. Its output hash is
`650b722fe4c8cc4a622dc78b75977bcd312bf8fe038341c7cc5e43c3782a6220`.

These findings establish a small user-space synchronization boundary. The
kernel's trap handlers, cross-process sharing, lifetime rules, compressed and
planar surfaces, and failure/concurrency behavior remain unresolved. The
private offsets are tied to this image; Absolute should model the observed
operations behind its own interfaces rather than treat those offsets as a
portable ABI.

## Headless behavior probes

The [owned probe](../script/research_graphics_probe.swift) passed five checks:

| Probe | Checked result |
| --- | --- |
| CoreGraphics bitmap | An 8-by-8 device-RGB bitmap filled red produced the expected RGBA bytes in all 64 pixels. |
| IOSurface | A nonplanar 8-by-8 BGRA surface reported 256 allocation bytes, 32-byte rows and four-byte elements. A write survived unlock and read locking; all four observed seed values were one in this run. |
| Metal buffer transfer | A submitted command copied 4,096 bytes; every byte matched. |
| Metal offscreen rendering | A 16-by-16 BGRA render target was cleared and read back. All 256 pixels matched within one UNORM step; the first pixel was `[64, 128, 255, 255]`. |
| Metal compute | A newly compiled, project-owned shader generated 1,024 integer values; every value matched the CPU reference. The pipeline reported a thread execution width of 32. |

The Metal device reported Apple M3 Max, unified memory, Apple GPU family 9 and
ray-tracing capability. Ray tracing itself was not exercised. No windows or
display capture were used, and display settings were not changed. These checks
are small macOS behavior oracles; they do not recover command packets, shader
instructions, scheduling, GPU firmware or an independent graphics driver.

## Hardware and firmware boundary

An allowlisted IORegistry observation identifies the running GPU service as
`AGXAcceleratorG15X`, bundle `com.apple.AGXG15C`, plug-in
`AGXMetalG15X_M1`, with 30 GPU cores and model Apple M3 Max. A filename suffix
alone should not be used to infer the chip generation. The installed AGXG15C
personality lists matching device names including `gpu,t6031`.

The separate boot/firmware investigation identifies this model's AGX
`armfw_g15c.im4p` and DCP `t603xdcp.im4p` payloads. Their presence and container
layouts do not establish the firmware's command protocols or implementation.
See [boot-firmware-findings.json](boot-firmware-findings.json) for identities
and the distinction between the installed restore set and a staged update.

As of this capture, Asahi's official table lists M3 Max GPU support as TBA and
DCP as WIP. Its August 2026 report describes an M3 DCP ABI target of macOS
14.8.3, which differs from this machine's macOS 27.0 installation. Treat that
version boundary explicitly before attempting hardware work. [Asahi M3 feature
table](https://asahilinux.org/docs/platform/feature-support/m3/),
[Linux 7.2 progress report](https://asahilinux.org/2026/08/progress-report-7-2/).

Mesa documents AGX analysis tools and an open graphics-driver stack, but that
does not establish support for this M3 Max. Its hardware notes are a reference
to compare against model-specific evidence. [Mesa Asahi documentation](https://docs.mesa3d.org/drivers/asahi.html).

## Next experiments for Absolute

1. Turn the explicit pixel format, color-space, row-stride, surface lifetime and
   completion observations into a portable surface/rendering contract. Replay
   the deterministic vectors through macOS and Linux backends.
2. Extend surface probes to cross-process ownership, errors, plane layouts and
   synchronization. Follow the selected kernel trap handlers before claiming
   IOSurface compatibility.
3. Analyze a bounded SkyLight `SLXServer` startup path and one window operation,
   then compare behavior with an owned test client. WindowServer's bootstrap
   does not explain the compositor or its private protocols.
4. Investigate AGX submissions and DCP/AGX firmware separately with exact chip
   and firmware identities. A bootable VM and software rendering can advance
   while bare-metal GPU support remains unresolved.

## Reproduce

From the project root, with the pinned REA tools and the existing local
Ghidra/Java/Xcode toolchains:

```sh
python3 script/research_graphics.py --probe
```

Without `--probe`, the script performs static analysis plus the read-only
IORegistry query. It does not run the owned graphics or linkage workloads.
Successful canonical REA records are reused only for the same executable hash;
cache observations are reused only when the macOS build and cache-map hash
match. `--refresh` recaptures the outputs and preserves changed prior bytes
locally. If a later build changes the expected code pattern, the script stops
instead of claiming the old interpretation applies.
