# Kernel-origin Mach send boundary

**Status: partial. The userspace Mach-message trap remains unresolved in this
kernel investigation.** This pass inspects the installed kernel's exported
kernel-origin send wrapper, its five immediate callees, and one disposition
table. It covers 3,944 code bytes in six function-start spans, 986 instruction
slots, and 24 data bytes. Those counts measure selected static evidence, not
complete function semantics or Mach compatibility.

The [machine-readable findings](mach-kernel-findings.json) retain source
identities, exact bounds, file offsets, hashes, direct call targets, and the
limits of each conclusion. The [capture script](../script/research_mach_kernel.py)
reproduces the bounded extraction and verifies retained evidence. Raw bytes,
synthetic code carriers, and disassembly stay in `research/local/mach-kernel/`.

## Evidence identity

- Host: macOS 27.0, build `26A5421a`.
- Installed artifact: `/System/Library/Kernels/kernel.release.t6031`.
- SHA-256: `ca7d17c39aa7a68ef280f3aa84e9d57a7c6be8630fa13d5a891e75db0fb9ae5e`.
- Mach-O UUID: `449CB33B-7B1E-3D30-8A86-BF2DCFA4B49F`.
- `LC_SOURCE_VERSION`: `13432.1.9`.
- Prior canonical REA `inspect_macho` evidence:
  `ev_65909f9a2ed46e58d4594cff09e4521adcb48b65b59faddbdf7cdb6765eb5dc6`.
- This pass:
  `absolute-mach-kernel-sha256:cc47181b49576241ee81bd1a0c1335bb8c95f4749b6c96d80ba8725ddba3fc48`.

Addresses below are unslid link-time addresses from the installed file. They
are not measurements of the live kernel. The previous REA metadata is reused
only after its artifact digest and UUID match. New disassembly comes from
Apple's `otool`; this pass adds no canonical REA function dossiers.

## Extraction boundary

The retained `nm -nm` output contains 6,947 symbol/address pairs. The script
independently parses `LC_SYMTAB` and verifies the entire pair set against the
installed file. Exact searches for `_mach_msg2_trap`, `_mach_msg_trap`,
`_mach_msg_overwrite_trap`, `_ipc_kmsg_get`, `_ipc_kmsg_copyin`, `_ipc_kmsg_send`,
and `_ipc_mqueue_send` find no matching names in that table. This does not
establish that their code is absent.

The exported `_mach_msg_send_from_kernel_proper` starts at
`0xfffffe0007364938`. Its next `LC_FUNCTION_STARTS` entry is
`0xfffffe00073649d4`, giving a 156-byte extraction span. Using the next
exported name as the boundary would incorrectly include other private
entries. The function-start table contains 22,991 entries; this is a metadata
count, not an assertion that every logical function is identified.

| Selected entry | Inferred role | Kernel file offset | Bytes |
| --- | --- | ---: | ---: |
| `0xfffffe0007364938` | Exported kernel send wrapper | 3,541,304 | 156 |
| `0xfffffe0007335f40` | Message copy stage | 3,350,336 | 588 |
| `0xfffffe000733618c` | Header and disposition stage | 3,350,924 | 1,328 |
| `0xfffffe0007331ff0` | Cleanup after early failure | 3,334,128 | 168 |
| `0xfffffe00073366bc` | Send dispatch stage | 3,352,252 | 1,244 |
| `0xfffffe00073322bc` | Cleanup after later failure | 3,334,844 | 460 |

Only the wrapper has an exact symbol name at its entry. The other labels are
inferred roles. Each extraction is contained in `__TEXT_EXEC,__text`, and the
segment and section mappings agree on its file offset. Every end is exclusive
and comes from the next function-start entry. These spans do not establish
complete logical function bodies or cover possible cold fragments.

## Findings

**KMSG-001 — The kernel header differs from the user header.** The local
Kernel.framework SDK declares the send API with a message pointer and a
send-size argument. Its structure-size assertion specifies a 32-byte kernel
header and a 24-byte user header. The first selected private stage uses the
32-byte minimum on the non-complex path. SDK declarations are separate
evidence; this report does not assert that the SDK source version matches
XNU `13432.1.9`.

**KMSG-002 — Failure cleanup depends on the stage reached.** The wrapper
calls the copy stage, then the header/disposition stage, then the dispatch
stage. A nonzero first-stage result returns directly. A second-stage failure
uses the early cleanup entry; a dispatch failure uses the later cleanup
entry. This is a static control-flow inference. It does not recover all
reference ownership or resource-release rules inside those helpers.

**KMSG-003 and KMSG-004 — Selected error paths are visible.** These are
static results for the kernel-origin path, not executed test cases:

| Condition in the selected path | Return value | Local SDK name |
| --- | --- | --- |
| Supplied size below 32 on the non-complex path | `0x1000000e` | `MACH_SEND_TOO_LARGE` |
| Null result from the buffer-producing callee | `0x1000000d` | `MACH_SEND_NO_BUFFER` |
| Internal 64-bit destination value is zero or all ones | `0x10000003` | `MACH_SEND_INVALID_DEST` |

The first size result is counterintuitive but is the branch value in this
artifact. It must not be substituted for the userspace trap's size-validation
rules. The destination check concerns an internal pointer sentinel, not a
task-local user port name. Complex messages and malformed trusted callers
require further analysis.

**KMSG-005 — Dispositions are normalized inside the kernel path.** The
header/disposition stage reads a six-word table at
`0xfffffe0007008ab0`, file offset `19,120`. Its 24-byte SHA-256 is
`66914d12635830874f0e971ea3d36a0bb90474061335499d64b829647c75cf0d`.
The address is independently decoded from its instruction pair. The selected
stage applies this table to the remote, local, and voucher disposition fields.

| Input code | Local SDK disposition | Table result |
| ---: | --- | ---: |
| 16 | `MACH_MSG_TYPE_MOVE_RECEIVE` | 16 |
| 17 | `MACH_MSG_TYPE_MOVE_SEND` | 17 |
| 18 | `MACH_MSG_TYPE_MOVE_SEND_ONCE` | 18 |
| 19 | `MACH_MSG_TYPE_COPY_SEND` | 17 |
| 20 | `MACH_MSG_TYPE_MAKE_SEND` | 17 |
| 21 | `MACH_MSG_TYPE_MAKE_SEND_ONCE` | 18 |

This establishes an internal normalization step. It does not establish valid
user rights, reference-count changes, or the contents of a user receive header.
The port-processing callee remains outside this pass.

**KMSG-006 — The wrapper supplies kernel-specific options.** The first
stage receives option value `0x2000050001`. Its low flags match the local
SDK's `MACH_SEND_MSG`, `MACH_SEND_ALWAYS`, and `MACH_SEND_NOIMPORTANCE`.
A thread-state bit can remove `0x40000` before dispatch. The high bit remains
unnamed in this report, and the dispatch stage also changes options in some
paths. These observations do not establish complete queue-limit or timeout
behavior.

## Remaining boundary and implementation use

| Question | Status |
| --- | --- |
| Installed artifact identity, selected addresses, and file mappings | Answered for this artifact |
| Exact bounded ranges for the wrapper and immediate callees | Answered as next-start spans |
| Selected kernel send failure and disposition paths | Partially answered by static inference |
| Complete queueing, scheduling, reference ownership, descriptors, and notifications | Unresolved |
| User `mach_msg2` trap entry and complete handler path | Unresolved |
| Userspace compatibility in Absolute | Requires separate owned-process observations and portable tests |

The direct-edge inventory exposes 24 additional target addresses outside the
six selected spans. Some have public symbols, including the aliased
`memcpy`/`memmove` entry. Exact symbol lookup is not a review of their behavior.
Indirect calls, conditional cross-function edges, and transitive callees are
outside the inventory's boundary.

For Absolute, the immediate value of this work is preserving the distinction
between user port names and internal kernel pointers, and between the two
header layouts. A portable user-message implementation needs behavior from
the owned-process reference oracle. This kernel wrapper cannot supply a
complete user-message contract.

## Reproduction

Run from the repository root:

```sh
python3 script/research_mach_kernel.py
python3 script/research_mach_kernel.py --check
```

The capture rejects a changed kernel digest before applying these
interpretations. It reads the installed file, verifies the prior metadata and
symbol capture, creates private inert `MH_OBJECT` carriers, and asks `otool`
to disassemble only the selected bytes. Check mode compares the retained
carriers to current source bytes, validates command/output records and
instruction-address coverage, and regenerates the public projection for an
exact comparison without rewriting it.

No installed OS component was modified. No kernel bytes were executed, no
live kernel or protected process was attached, and no Apple implementation
source, disassembly, or pseudocode is included in this public report.
