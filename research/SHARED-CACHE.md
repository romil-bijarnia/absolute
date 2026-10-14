# Shared cache and kernel entry conventions

Captured on 14 October 2026 from macOS 27.0, build 26A5421a. The active arm64e
cache inventory contains 4,083 image paths and 89,379 declared dependency
edges. Eleven selected functions in `libsystem_kernel` were inspected at the
instruction level. These are separate measures: complete metadata inventory
for this cache is not complete reverse engineering of those images or macOS.

The public projection is [shared-cache-findings.json](shared-cache-findings.json).
The complete image/dependency graph, tool output, and selected code evidence
remain in the Git-ignored `research/local/shared-cache/` directory. No Apple
code, binary carrier or disassembly listing is included in this public report.

## Cache inventory and verification

`dyld_info -arch arm64e -uuid -platform -linked_dylibs -all_dyld_cache` returned
exactly the same 4,083 paths as the installed cache map. An independent parser
read the mapping tables across 80 cache files, located every image's Mach-O
header, and checked its `LC_UUID` against the tool output. All 4,083 UUIDs
matched. The parser uses bounded reads of the cache mapping/header format
described by [Apple's dyld cache header](https://github.com/apple-oss-distributions/dyld/blob/main/include/mach-o/dyld_cache_format.h).

| Declared dependency relationship | Edges |
| --- | ---: |
| Target exactly matches an inventoried cache path | 89,340 |
| Filesystem symlink resolves the target to a cache path | 11 |
| Target remains outside the bounded catalog | 28 |
| Total | 89,379 |

The unresolved set contains 27 weak declarations and one ordinary declaration:
`libramrod.dylib` names `/usr/lib/libimg4.dylib`. The latter path was neither in
the map nor present as an ordinary file in this capture. That observation does
not establish a runtime loader failure. Resolution in a restore environment,
optional code paths and other delivery mechanisms remain unexamined.

Platform declarations divide into 2,016 macOS images, 520 Mac Catalyst images
and 1,547 images marked `zippered(macOS/Catalyst)`. There are 3,999 declarations
with minimum version 27.0; the remainder declare older minimum versions.
These are binary declarations, not independently tested deployment claims.

The most frequently declared dependency is `libSystem.B.dylib`, with 4,037
incoming edges, followed by `libobjc.A.dylib` with 3,491 and Foundation with
3,447. This helps prioritize compatibility boundaries; it does not rank the
amount of code required to implement them.

## Architecture and version identity

`/usr/lib/system/libsystem_kernel.dylib` also exists as a universal file with
x86_64, arm64 and arm64e slices. The initial unrestricted tool capture included
all three. The evidence used below explicitly selects arm64e; mixing labels
from an unrestricted disassembly would produce contradictory conventions.

The selected image UUID is `1D409488-002C-3663-9BA9-37C334D384C1`. Its
`LC_SOURCE_VERSION` is `13432.1.9`, matching the numeric XNU version in the
running kernel string. The macOS 27.0 SDK stub in the earlier kernel ABI report
declares `13432.1.6`. Those patch versions are recorded separately. SDK
declarations are a comparison reference, not a substitute for the installed
implementation.

The standalone image and cache share the UUID, but their instruction bytes are
not universally identical: five of the eleven selected bodies contain changed
data-address instructions after cache construction. The script retained each
selected body's actual cache bytes, wrapped them in a minimal local Mach-O
object solely for `otool`, and inspected the cache-specific disassembly. These
private carriers preserve the original unslid instruction addresses. Both
versions' hashes and the changed instruction offsets are in the public JSON.

## BSD entry stubs and errors

| API | Selected function label | Selector in `x16` | SDK `SYS_` value |
| --- | --- | ---: | ---: |
| `read` | `_read` | 3 | 3 |
| `write` | `_write` | 4 | 4 |
| `getpid` | `___getpid` | 20 | 20 |

All three use `svc #0x80`. The selector encodings were checked again against
the actual cache bytes. The numbers match the existing 466-entry SDK table in
[kernel-abi-findings.json](kernel-abi-findings.json). The `_getpid` export and
`___getpid` export resolve to the same image offset, `0x1164`.

The read/write stubs place the selector in `x16` without rearranging argument
registers. After the supervisor call, they use a carry-clear branch as the
success path and return the result in `x0`. The error path calls `cerror`.
That helper preserves the error value, invokes a function-table callback,
then calls `cerror_nocancel`. The callback's wider behavior is unresolved here.

`cerror_nocancel` stores the error code in a global slot, reads `TPIDRRO_EL0`,
and loads a pointer at offset eight from that thread register. If the pointer
is nonzero, it stores the error there as well. It then returns with both `x0`
and `x1` set to minus one. This is a concrete user-space error/TLS convention;
the kernel code that sets the syscall return flags was not analyzed.

The getpid implementation first reads a cached 32-bit PID. A positive value
returns immediately. Otherwise it issues syscall 20, follows the same
carry-clear success convention, and makes a single exclusive-store attempt
to populate an empty cache slot. Cache invalidation during fork and other
process transitions remains outside this pass.

## Mach traps, retry handling and VM fallback

| Function | Selector in `x16` | Stub behavior |
| --- | ---: | --- |
| `mach_msg2_trap` | -47 | `svc #0x80`, then return. |
| `_kernelrpc_mach_vm_allocate_trap` | -10 | `svc #0x80`, then return. |
| `_kernelrpc_mach_vm_deallocate_trap` | -12 | `svc #0x80`, then return. |

Each of these three entry stubs is three instructions. They leave incoming
argument registers untouched apart from the selector register and return the
Mach status directly. They do not call the BSD errno helper. These negative
Mach selectors are a distinct namespace from the positive BSD syscall table.

The 64-instruction `mach_msg2_internal` wrapper adds behavior above the trap:
it strips the send/receive interrupt-option bits before the initial call,
checks the returned status, and has retry paths for interrupted sends and
receives when the caller did not request interruption to be returned. The
comparisons and flag tests match these installed SDK constants:

| SDK constant | Value |
| --- | --- |
| `MACH_SEND_INTERRUPT` | `0x00000040` |
| `MACH_RCV_INTERRUPT` | `0x00000400` |
| `MACH_SEND_INTERRUPTED` | `0x10000007` |
| `MACH_RCV_INTERRUPTED` | `0x10004005` |
| `MACH_SEND_INVALID_DEST` | `0x10000003` |

The receive retry path also changes the packed arguments and option mask.
Their complete message-layout semantics have not been reconstructed. No
interrupted-call runtime experiment was performed in this pass.

`mach_vm_allocate` and `mach_vm_deallocate` first call their respective fast
trap. A result of `0x10000003` selects a call to the corresponding
`_kernelrpc_mach_vm_*` routine. Their wrappers also contain optional logging
callback paths. The destination routine and the kernel's allocation,
protection, scheduling and IPC internals remain unexamined.

Across the eleven selected functions, 228 instructions were inspected. The
existing kernel ABI report separately records 26 passing checks on owned Mach
ports, memory, semaphores, pipes, kqueue and time. Those runtime checks do not
test every branch described above, and this static pass executed no guessed
trap numbers.

## What the GPU file records establish

The earlier system inventory contains 229 slices with CPU type `0x01000013`
across 29 files. The local SDK's `mach-o/loader.h` defines file type `0xd` as
`MH_GPU_EXECUTE`; `otool -hv` also identifies the sampled metallib slices as
GPU executables.

The CPU-type value contains the `CPU_ARCH_ABI64` flag and base value 19. The
installed `mach/machine.h` explicitly skips base value 19, `otool` prints the
numeric CPU type, and `lipo -archs` reports unknown architecture labels for the
sample. Therefore this pass establishes the GPU-program file type and numeric
architecture tag, but does not assign a verified name such as AIR64 or map
the subtype values to specific chips. These counts do not represent 229
understood GPU implementations.

## Implications for Absolute

The shared-cache catalog provides a concrete dependency graph for choosing
implementation boundaries. The syscall findings provide initial contracts
for an eventual compatibility layer: selectors, argument preservation,
carry/error handling, errno storage, Mach return conventions, and selected
retry/fallback behavior need independent conformance tests. Calling a Linux
syscall with a macOS selector does not implement those contracts.

The next useful code investigation is the kernel-side dispatch and one owned
Mach-message path, tied to a matching kernel collection/source identity.
Further metadata inventory should be counted separately from behavior
reconstruction. Dynamic library loading, Objective-C/Swift runtimes, complete
Mach IPC, process semantics and graphics compatibility remain substantial
unresolved work.

## Reproduce

```sh
python3 script/research_shared_cache.py
```

The script uses the installed Xcode tools, active arm64e cache and existing
kernel/system inventory reports. It validates the map, all image UUIDs, six
cached selector encodings, getpid export aliasing and three SDK selector
comparisons. It saves complete evidence locally and a concise public
projection. `--refresh` repeats capture and archives changed prior outputs.
No system component or security setting is changed.
