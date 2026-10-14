# SPTM and TXM startup-code analysis

This extends the [firmware container investigation](BOOT-FIRMWARE.md) into
native code. The inputs are the decoded monitor payloads from the current
macOS 27.0 / 26A5421a restore set. Neither image was executed.

Apple's installed `otool` decoded the `LC_UNIXTHREAD` program counters.
REA/Ghidra then produced three canonical function dossiers:

| Image and routine | Address | Ghidra body | Evidence ID |
| --- | --- | ---: | --- |
| SPTM entry branch | `0xfffffff0270ac388` | 4 bytes | `ev_220b582aaeb8b9b5da8ce0ff1df270718b4e5e70e4b22fdf3dad9d048a51b399` |
| SPTM branch target | `0xfffffff0270af000` | 6,160 bytes | `ev_4f1d84124bd589a6790382bd28042e00f4ce6d1484e175a8c8ce5545ceff933b` |
| TXM entry | `0xfffffff01708c000` | 96 bytes | `ev_c97a4cb8e01474fbaf5907cc5766fe42a075786925205b2abce2d05f76a135e1` |

## SPTM observations

The entry is a single branch to the startup routine. Ghidra also displayed
the target's pseudocode through the entry thunk, so the target was analyzed
separately to obtain its actual body ranges and assembly. Its two recorded
ranges contain 1,540 instructions; the enclosing span includes a gap and is
not treated as one continuous code body.

The initial assembly writes `OSLAR_EL1` and `DAIFSet`, retains the incoming
structure pointer, and conditionally uses a pointer at input offset `0x480`.
When the first input field passes the signed comparison against three and
that pointer is nonzero, it clears `0x17c0` bytes and writes an SPTM marker
and the constant five. The full input-structure contract is not established.

The inspected setup writes `VBAR_EL1`, branches on `CurrentEL`, and contains
an EL2-specific sequence involving `HCR_EL2` and `CNTVOFF_EL2`.
Later instructions write `TCR_EL1`, `TTBR0_EL1`, `TTBR1_EL1` and `MAIR_EL1`,
with synchronization and TLB operations around them.

**Inference:** this code participates in early exception and address-mapping
setup. The dossier also contains implementation-specific system-register
accesses, unresolved semantics and decompiler warnings about removed blocks.
It does not establish every mapping rule, policy decision, supported entry
state or later monitor operation.

## TXM observations

The 24-instruction entry first tests bit 63 of `x18` and can branch to an
alternate routine. On the inspected setup path it takes a stack address
from the incoming structure and tests the low 14 bits. A nonzero result
branches to a diagnostic failure path.

For the aligned path it places the stack at offset `0x3c00` within that
16-KiB region, clears a byte and a word in its initial stack storage, calls
three helpers, and branches to another routine while retaining the incoming
structure pointer. Those helpers and the alternate path were identified as
follow-up targets; their policies were not reconstructed here.

## Evidence and limits

[boot-monitor-findings.json](boot-monitor-findings.json) records image hashes,
load-command hashes, exact function-body ranges, callees, REA identities and
provider limitations. Complete assembly and pseudocode stay under
`research/local/boot-firmware/`.

These are static interpretations of small startup boundaries. They do not
implement SPTM or TXM, reproduce firmware policy, establish hardware behavior,
or replace a boot-time execution test. Boot ROM, LLB, SEP code and the wider
device-firmware protocols remain open.

```sh
python3 script/research_boot_firmware.py --rea
python3 script/research_boot_monitors.py
```

Matching function records are reused by input hash and procedure address.
Ghidra imports are temporary, and original firmware bytes are preserved.
