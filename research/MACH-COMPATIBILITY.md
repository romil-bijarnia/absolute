# Portable inline Mach-message component

Absolute now includes an original Swift module, `AbsoluteMach`, that implements
the measured in-process, nonblocking inline-message subset on macOS and Linux.
Its behavior is checked against the independent
[native reference](MACH-MESSAGES.md), captured on macOS 27.0 / 26A5421a.

## Implemented boundary

`MachMessageHeader` and `MachMessage` encode and decode the 24-byte little-endian
user header and opaque payload. The codec retains bytes after the declared
message size separately, including trailers. It checks bounds, handles sliced
data safely, preserves signed message IDs and exposes disposition fields.

`MachPortSpace` supplies a namespace whose operations are serialized:

- Allocate receive rights, add send references, inspect rights and queue state,
  and release receive, send and dead-name references.
- Queue inline messages with COPY_SEND or MOVE_SEND, preserving FIFO order.
- Treat the send-size argument independently from the header's size field.
- Return the observed size/disposition errors and zero-timeout outcomes.
- Return an additional send reference after a full-queue COPY_SEND timeout,
  rewrite it as MOVE_SEND, and consume it correctly when the caller retries.
- Include the eight-byte default receive trailer in capacity accounting.
- Preserve a too-large message with the LARGE behavior, or consume it and return
  the observed minimal header/trailer without LARGE.
- Convert remaining send references to dead-name references when the receive
  right is destroyed, and remove the name after its final reference is released.

The API returns the failed send's buffer explicitly because it can represent
a returned right. Discarding that buffer and retrying the original COPY_SEND
would lose the observed ownership information.

## Independent conformance checks

The C oracle creates its own native ports and captures **23 scenarios and 211
checks**. Two processes produced identical normalized observations. The Swift
tests replay all **386 recorded operations** in order and compare statuses,
rights, queue state, message bytes, trailer bytes and post-receive queue counts.

The replay runs twice on each host. The second pass reserves names first so
the fixture's token one maps to another implementation name. This checks that
agreement depends on namespace relationships, rather than coincidental numbers.

Both replay passes and the unsupported-request state checks pass on macOS and
Linux. The complete suites pass **44 unit tests on macOS, 43 on Linux, and 16
CLI integration checks on each**. The extra Mac test compares the codec's bytes
with the installed SDK's native C header structure.

The source-bound validation record is
[implementation-verification.json](implementation-verification.json). The
[component record](mach-compatibility.json) binds the reference identity,
implementation files, test files and demo outputs.

## Try it

```sh
swift run absolute mach-demo
```

The command sends a small inline payload through a fresh Absolute namespace,
receives and validates the transformed header and trailer, then releases the
rights. It reports its scope and checks as JSON. The regular core verifier also
runs this demonstration, including inside the Linux VM.

```sh
./script/check_core.sh
./script/check_linux.sh
```

## Remaining work

The namespace lives inside one process. It does not currently provide a
system-wide transport, cross-process isolation, descriptor transfers, reply or
send-once rights, vouchers, port sets, notifications, blocking waits, traps or
execution of macOS binaries. Those remain separate implementation contracts.

Complex bodies can pass through the layout codec as opaque data; the namespace
rejects them explicitly. Unsupported features use implementation errors rather
than fabricated Mach status codes.

This component also chooses its own resource bounds: 4,096 live names, one MiB
per message, 16 MiB of queued message data, and queue limits from one to 1,024.
Those are implementation bounds; the reference did not establish the native
maximums. Name generation, exhaustion, races, concurrent destruction and
untested native option combinations remain outside the conformance claim.

The separate [kernel investigation](MACH-KERNEL.md) inspects six kernel-origin
send spans. Its 32-byte internal header and kernel-only error paths are not
used as rules for this 24-byte user-message implementation.
