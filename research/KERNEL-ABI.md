# Kernel interfaces and owned-process behavior

Reference: macOS 27.0 / 26A5421a, running Darwin kernel
`xnu-13432.1.9~3/RELEASE_ARM64_T6031`, with the installed macOS 27.0 SDK.
The [capture script](../script/research_kernel_abi.py) separates SDK declarations
from behavior observed in a new process using its own kernel objects.

## Declared ABI

Clang preprocessing of the installed `sys/syscall.h` produced **466 named
syscall constants**, all with distinct numbers. The greatest defined number
is 557; `SYS_MAXSYSCALL` is 558. Gaps and reserved slots are not counted as
implemented handlers.

Apple's `llvm-readtapi` converted the ARM64e slices of the libSystem, Objective-C
and C++ runtime stubs into structured records. These contain **43 library
declarations and 12,204 symbol declarations**, including embedded/reexported
libraries. Symbol presence is not an implementation or compatibility test.
Conversion of version 4 stubs to version 5 cannot recover whether each symbol
originally represented code or data.

The exact header/stub hashes and syscall name-to-number mapping are in
[kernel-abi-findings.json](kernel-abi-findings.json). Installed implementation
stubs are examined separately in [SHARED-CACHE.md](SHARED-CACHE.md).

## Runtime observations

The [C probe](../script/research_kernel_probe.c) passed **26 checks**:

- Allocate a receive right, insert a send right, inspect its reference count,
  send/receive a 32-byte message, preserve its ID and payload, observe an empty
  receive timeout and invalid destination, and release both owned rights.
- Allocate a zero-filled page, write it, switch it to read-only, query the
  region's protection, restore write access, verify data, and deallocate it.
- Create a zero-count semaphore, observe a timeout, signal it, consume the
  signal exactly once, and destroy the semaphore.
- Register an owned pipe with kqueue, observe the exact readable byte count,
  read the payload, and verify that the drained pipe is no longer readable.
- Observe an advancing Mach clock with a nonzero timebase.

This run reported a 16,384-byte VM page and Mach timebase numerator/denominator
125/3. The empty receive returned `0x10004003`; the null-destination send
returned `0x10000003`; the semaphore timeout returned 49.
These are captured observations on this target, not assumptions for other
architectures or versions.

The probe allocates only its own ports, memory, semaphores and descriptors.
It uses receive/send timeouts, closes the objects it creates, and does not
attach to another task or call guessed syscall numbers.

## Source matching and remaining work

Apple publishes [XNU](https://github.com/apple-oss-distributions/xnu),
[dyld](https://github.com/apple-oss-distributions/dyld), and
[Libc](https://github.com/apple-oss-distributions/Libc) source repositories.
The exact `xnu-13432.1.9` tag query returned HTTP 404 in this pass; the five
sampled tag records were from the `12377` series. This is a bounded repository
query, not proof that a matching source release exists nowhere.
The retained query is `research/local/kernel-abi/source-match.json`.

No scheduler, full VM subsystem, Mach RPC system, exception server, syscall
emulator, or kernel replacement was implemented by these probes. Concurrency,
cross-process rights transfer, out-of-line message descriptors, failure races
and full syscall semantics remain open.

Evidence identity:
`absolute-kernel-abi-sha256:bbb7fb1debddf46b49d159a5535481a7134dd489661f45ea6df228a88e25f6d4`.

```sh
python3 script/research_kernel_abi.py
python3 script/research_kernel_abi.py --static-only
```

The default command compiles and runs the owned probe. Static-only mode
captures declarations without running it. Every capture retains source, binary
and input identities under `research/local/kernel-abi/`.
