# Bounded Mach-message reference

This reference captures `mach_msg` behavior in fresh processes on macOS 27.0,
build 26A5421a, with Darwin `xnu-13432.1.9~3/RELEASE_ARM64_T6031` and SDK
`macosx27.0`. Every port belongs to the probe process. No other process was
attached and no system service was changed.

The independent C oracle ran **23 scenarios with 211 checks**. Two fresh
processes produced identical normalized JSON. The check count includes setup,
cleanup, and repeated conditions; it is not a count of distinct Mach features.

The full reference is [mach-message-findings.json](mach-message-findings.json).
The identical publishable fixture is
[Tests/AbsoluteMachTests/Fixtures/mach-message-reference.json](../Tests/AbsoluteMachTests/Fixtures/mach-message-reference.json).
It contains source, binary, compiler, SDK/header, host, and raw-capture identities,
as well as an ordered operation journal for every scenario.

## Admitted observation boundary

The messages contain inline bytes only. On send, local/reply and voucher names are null;
no complex descriptors, out-of-line memory, port arrays, or voucher rights are
used. Send and receive both specify a **zero timeout**. Queue limits of one and
two are exercised; a newly allocated port reports a default limit of five.
Receive storage is physically 256 bytes, while the declared capacity varies
independently. Receive buffers begin zero-filled.

These observations establish a narrow local API contract. They do not establish
cross-process rights transfer, task isolation, notification behavior, scheduling,
concurrent destruction, or the complete Mach IPC implementation. They are not
proof that macOS binaries can run on another operating system.

## Header and byte layout

The observed header is 24 bytes, followed by inline payload bytes. Port names
are 32-bit values at offsets 8, 12, and 16. The supplied message identifier is
preserved on successful receive. In the common scenario, 16 payload bytes make
a 40-byte message. The returned `msgh_size` excludes the trailer.

Port-name words are normalized to scenario-local roles: token 1 means the
created destination, zero means null, and `0xffffffff` denotes the reserved
dead-name sentinel. A name whose right becomes dead still retains its destination
role; its right state changes. All remaining observed header and payload bytes
are retained exactly. No real task port names are published.

For a COPY_SEND message with identifier `0x414d0001`, the normalized send bytes
are:

```text
130000002800000001000000000000000000000001004d41010003020504070609080b0a0d0c0f0e
```

The successful receive bytes are:

```text
001100002800000000000000010000000000000001004d41010003020504070609080b0a0d0c0f0e
```

The sender's destination becomes the receiver's local port. The received remote
port stays null. Both COPY_SEND and MOVE_SEND produce received bits `0x1100`:
remote disposition zero, local disposition PORT_SEND (17). The default trailer
follows at offset 40 and contains type zero and size eight:

```text
0000000008000000
```

The native call has an independent `send_size` argument. A header declaring
size 24 with a `send_size` argument of 40 was accepted and received as size 40.
The sender's buffer was unchanged after this successful send. A byte codec may
validate its own declared-size buffer format; that validation is a separate
contract from the native call's size argument.

At the tested sizes, 24, 28, and 40 bytes were accepted. Sizes 20, 25, 27, and 39
returned `MACH_SEND_MSG_TOO_SMALL`. The admitted sending subset therefore needs
a complete header and four-byte size alignment; untested larger-size limits are
not established here.

## Rights and failed sends

| Operation | Observed sender reference effect | Returned message-buffer effect |
| --- | --- | --- |
| Successful COPY_SEND | Send user references stay at 1 | Header stays COPY_SEND (19). |
| Successful MOVE_SEND | Send user references fall from 1 to 0 | Header stays MOVE_SEND (17). |
| MOVE_SEND to a full queue | The consumed reference is restored; count stays at 1 | Timeout header has MOVE_SEND (17). |
| COPY_SEND to a full queue | An additional reference is returned; count rises from 1 to 2 | Timeout header changes from COPY_SEND (19) to MOVE_SEND (17). |
| Retry the returned MOVE_SEND after draining the queue | Count falls from 2 to 1 | Send succeeds and the returned additional reference is consumed. |

A COPY_SEND timeout is therefore an ownership event, not just a status code.
The returned header represents a returned send reference. The FIFO scenario
retains that returned header, drains the queued messages, retries it, and checks
that the additional reference is consumed while the original reference remains.

A full-queue test also supplied header size 24 with `send_size` 40. On both COPY
and MOVE timeout, error copy-out changed the returned header size to 40. COPY
increased send user references from one to two; the following MOVE timeout left
them at two. The queue still contained only its original message.

COPY_SEND on a receive-only name returned `MACH_SEND_INVALID_DEST`. Supplying
remote disposition zero or MOVE_RECEIVE (16) returned `MACH_SEND_INVALID_HEADER`
and did not enqueue a message. Other disposition combinations are outside this
capture.

For an existing name, `mach_port_get_refs` returned success and a count of zero
for a right kind that was absent. An exploratory expectation of
`KERN_INVALID_RIGHT` was disproved; that initial capture is retained locally.

## Receive capacity and destruction

A 40-byte message requires capacity 48 under the captured default trailer
options. Capacities 24, 32, and 40 all return `MACH_RCV_TOO_LARGE`, even though
capacity 40 fits the message bytes alone.

| Declared capacity | LARGE flag | Queue effect | Header and trailer observation |
| --- | --- | --- | --- |
| 24, 32, or 40 | Present | Message remains queued. A later larger receive succeeds. | Required message size is 40. Other zero-initialized header fields stay zero. No trailer is returned. |
| 24 | Absent | Message is consumed. A later receive times out. | Minimal received header has size 24 and bits `0x1100`; no trailer fits. |
| 32 or 40 | Absent | Message is consumed. A later receive times out. | Minimal received header has size 24 and bits `0x1100`; the eight-byte default trailer appears at offset 24. |
| 48 | Either | Message is consumed successfully. | Header size 40, original inline payload, and the eight-byte trailer at offset 40. |

The LARGE error reports the required **message size**, not the capacity including
its default trailer. Callers must account for the trailer separately. Error
buffers are partial results, not complete messages that happen to have an error
status. The 64-byte storage snapshots in the fixture show initialized storage;
they do not imply that the kernel wrote every observed byte.

Two queued messages are received in FIFO order. A nonblocking receive on an
empty queue returns `MACH_RCV_TIMED_OUT`. Destroying the receive right makes a
retained send name a dead name with one dead-name user reference. Sending then
returns `MACH_SEND_INVALID_DEST`; receiving returns `MACH_RCV_INVALID_NAME`.
Deallocating that dead-name reference removes the name, after which name queries
return `KERN_INVALID_NAME`.

## Relevant status constants

The fixture records the values emitted by the compiled SDK expressions.
Selected statuses are:

| Name | Hex value |
| --- | --- |
| MACH_MSG_SUCCESS | `0x00000000` |
| MACH_SEND_INVALID_DEST | `0x10000003` |
| MACH_SEND_TIMED_OUT | `0x10000004` |
| MACH_SEND_MSG_TOO_SMALL | `0x10000008` |
| MACH_SEND_INVALID_HEADER | `0x10000010` |
| MACH_RCV_INVALID_NAME | `0x10004002` |
| MACH_RCV_TIMED_OUT | `0x10004003` |
| MACH_RCV_TOO_LARGE | `0x10004004` |
| KERN_INVALID_NAME | `0x0000000f` |

## Reproduction and fixture format

```sh
python3 script/research_mach_messages.py
```

The script copies the source and capture script into a new local capture,
compiles the C oracle against the selected SDK, runs it twice, and verifies
that the normalized results are identical and all checks pass. Only then does
it update the public JSON and test fixture. `--capture-only` retains a new
capture without changing those published artifacts. `--repetitions N` accepts
one through eight runs; two is the default.

The wrapper has `schema`, `evidence_id`, `evidence_type`, `provenance`,
`repeatability`, `oracle`, and `limitations` keys. `oracle.scenarios` contains
ordered `operations`, including inputs, results, normalized buffers, observed
port states, and condition checks. Port-state values must be interpreted with
their associated query statuses. `queue_count_after: null` means a receive queue
could not be queried for the name. Initial zero-filled error fields are not a
claim that the kernel clears arbitrary preexisting buffer contents.

This oracle does not import or run Absolute's IPC implementation. Its checked-in
fixture is suitable for independent replay comparisons. This report describes
the reference observations; implementation and conformance claims require their
own results.

Evidence identity:
`absolute-mach-messages-sha256:e5723631bb484e1e5036b2f4314a1823d241c7995c1e365efbed04b19de9ad3e`.
