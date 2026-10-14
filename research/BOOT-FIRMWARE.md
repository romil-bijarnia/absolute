# Boot, kernel collections, and device firmware

This pass identifies and parses installed boot artifacts. It does not establish a
complete macOS boot implementation, a firmware replacement, or working bare-metal
hardware support for Absolute.

A subsequent [startup-code pass](BOOT-MONITORS.md) analyzes the SPTM entry,
its direct branch target, and the TXM entry. Full monitor behavior remains open.

Captured on 2026-10-14, macOS 27.0, build 26A5421a. The machine's selected restore
manifest declares device class `j514map`; the shipped device-tree template declares
`arm-io,t6031`. These are product/model identifiers, not machine serial numbers.

## Measured coverage

The reproducible [inspector](../script/research_boot_firmware.py) reads static
formats and records content identities in [boot-firmware-findings.json](boot-firmware-findings.json).
Its complete local record is `research/local/boot-firmware/capture.json`.

| Artifact boundary | Records | Work completed |
| --- | ---: | --- |
| `/System/Library/Kernels` | 14 | Sizes, SHA-256 identities, supported Mach-O headers and load commands |
| `/usr/standalone` | 109 | Regular-file inventory and hashes; symbolic links and hidden entries excluded |
| Preboot `restore` | 18 | Seventeen model-specific IM4P firmware/tree images and one kernelcache |
| Preboot `restore-staged` | 18 | Same bounded format inspection for the staged version |
| Preboot boot-object directory | 21 | Public IM4P payload metadata and hashes inside IMG4 containers |

This is **180 artifact records**, not 180 fully understood components. Seven
images in each restore set use LZFSE and were successfully decompressed. Seventeen
boot-directory payload hashes match the current restore payloads exactly. IMG4
type names can differ despite identical payload bytes: the DCP restore wrapper
uses `dcpf`, while its boot wrapper uses `dcp2`.

The restore manifest is **27.0 / 26A5421a**; the staged manifest is **27.2 /
26B5091g**. Staged files are not evidence that their code is running. No firmware
was launched, flashed, or modified.

## Actual images and structures

The current restore set contains these observations:

| Component | Observed format or identity | Remaining boundary |
| --- | --- | --- |
| iBoot | IM4P `ibot`, `mBoot-20457.1.29`; LZFSE decodes to 2,792,368 bytes | Flat payload; control flow and hardware initialization not reconstructed |
| iBootData | IM4P `ibdt`, same version; 744,784 decoded bytes | Configuration semantics not reconstructed |
| DeviceTree | IM4P `dtre`; 406,948 decoded bytes; **548 nodes, 6,753 properties**, fully consumed by the parser | Static template; runtime additions were not captured |
| Kernelcache | IM4P `krnl`; 124,911,616 decoded bytes; arm64e `MH_FILESET`, **355 embedded image declarations** | Inventory does not explain each driver's behavior |
| SPTM | IM4P `sptm`; arm64e `MH_EXECUTE`, 1,376,288 decoded bytes | Startup partially inspected separately; complete monitor implementation unresolved |
| TXM | IM4P `trxm`; arm64e `MH_EXECUTE`, 589,856 decoded bytes | Entry partially inspected separately; policy implementation unresolved |
| DCP display firmware | IM4P `dcpf`; arm64e `MH_PRELOAD`, 10,035,200 decoded bytes | Display protocol, modesetting, and scheduling remain separate work |
| AOP, ANE, AVE | Direct arm64e Mach-O payload headers | Subsystem protocols not reconstructed |
| SIO, ISP, PMP | Direct arm64 Mach-O payload headers | Subsystem protocols not reconstructed |
| AGX GPU, MTP, InputDevice, Multitouch | IM4P payloads identified and hashed; payload headers are outside this parser's recognized Mach-O/LZFSE formats | Further container/code interpretation required |
| SEP | IM4P `sepi`, 5,931,008 opaque payload bytes | No decrypted sepOS, SEP ROM, or cryptographic key material recovered |

The kernelcache declares `com.apple.kernel`, `com.apple.AGXG15C`,
`com.apple.driver.AppleDCP`, `com.apple.driver.RTBuddy`, multiple SEP drivers,
and T6031-specific ANE, PCIe and power-management drivers. This establishes
packaging, not the running state or complete behavior of those drivers.

The standalone `kernel.release.t6031` is 17,082,360 bytes with 31 Mach-O load
commands and 6,947 declared symbol-table entries. Its SHA-256 is
`ca7d17c39aa7a68ef280f3aa84e9d57a7c6be8630fa13d5a891e75db0fb9ae5e`.
REA independently inspected this file and the decoded SPTM and TXM images.

## Boot and hardware boundaries

Apple documents the application-processor boot chain as Boot ROM, LLB, then iBoot.
LLB verifies system-paired firmware and the locally signed boot policy; iBoot
loads OS-paired firmware and kernel collections and verifies the system-volume
root hash. This describes the platform architecture; our static capture does not
observe that sequence executing. [Apple boot process](https://support.apple.com/guide/security/secac71d5623/web).

The SEP has its own immutable Boot ROM and verifies sepOS before running it.
Finding `sep-firmware...im4p` on disk does not provide the chip's ROM, plaintext
SEP code, or its device-bound secrets. [Apple Secure Enclave](https://support.apple.com/guide/security/secure-enclave-sec59b0b31ff/web).

SPTM and TXM form an additional page-table and execution-policy boundary on
supported M2-and-later systems. Their presence here must be accounted for in
any model of this Mac's boot/runtime architecture. [Apple operating-system integrity](https://support.apple.com/guide/security/operating-system-integrity-sec8b776536b/web).

The static device tree supplies concrete discovery seeds: `aic,3` for interrupts,
`pmgr1,t6031` for power management, `dart,t8110` for IOMMU nodes,
`uart-1,samsung` for `uart0`, and `iop,ascwrap-v6` for ANS, DCP, AOP, SIO,
SMC, MTP and ANE coprocessor nodes. SEP declares `iop-sep,ascwrap-v6` instead.
These compatible strings do not establish register or message semantics.

Useful implementation interfaces are already documented elsewhere:

- **Kernel handoff:** XNU's public `boot_args` declaration includes memory bases
  and size, framebuffer information, a device-tree pointer/length, command line,
  and boot flags. It is a source reference, not proof that every field and offset
  matches this installed build. [XNU boot header](https://github.com/apple-oss-distributions/xnu/blob/main/pexpert/pexpert/arm64/boot.h).
- **Coprocessor transport:** Linux's Apple RTKit implementation supplies endpoint
  negotiation, power-state messages and shared-memory support over the Apple
  mailbox layer. Each device still needs its own protocol implementation and
  version handling. [Linux RTKit implementation](https://github.com/torvalds/linux/blob/master/drivers/soc/apple/rtkit.c).
- **Open OS handoff:** m1n1 bridges Apple's boot environment to Linux, initializes
  hardware, accepts device-tree/kernel/initramfs payloads and can chainload a
  second stage. This is an existing replacement boundary for the OS loader; it
  does not replace Boot ROM or every device firmware image.
  [m1n1 user guide](https://asahilinux.org/docs/sw/m1n1-user-guide/),
  [Apple Silicon platform introduction](https://asahilinux.org/docs/platform/introduction/).

As of this review, Asahi's M3 feature table lists M3 Max GPU support as **TBA**
and DCP support as **WIP**, while boot-framebuffer output is listed for relevant
MacBook Pro models. A Linux desktop working in a virtual machine does not establish
accelerated graphics on this Mac's physical GPU.
[M3 support matrix](https://asahilinux.org/docs/platform/feature-support/m3/).

## Absolute replacement boundary

For the next bootable-VM milestone, Absolute can package its Linux kernel,
initramfs, root filesystem and desktop session against virtual hardware. That
milestone can be verified independently of the Mac's physical firmware.

Physical-Mac support requires a separate target: a reviewed boot handoff, the
correct device tree, supported drivers, and the required firmware interfaces.
Replacing each device's firmware is another project within that target. No
Boot ROM, NOR firmware dump, sepOS implementation, full driver protocol, or
new bare-metal boot path was produced in this pass.

## Evidence and reproduction

| Observation | Evidence identity |
| --- | --- |
| Complete static capture | `absolute-boot-capture-a8e3f99b08c9358e2222` |
| Current restore manifest | `absolute-boot-manifest-fd85d000b1867da650ef` |
| Current DeviceTree image | `absolute-boot-artifact-cd8bfdeea8288764682c` |
| Current kernelcache image | `absolute-boot-artifact-1eb8ff6aefe51877b0b3` |
| Current iBoot image | `absolute-boot-artifact-6eb74917b577a6dadbc7` |
| REA kernel Mach-O inspection | `ev_65909f9a2ed46e58d4594cff09e4521adcb48b65b59faddbdf7cdb6765eb5dc6` |
| REA SPTM Mach-O inspection | `ev_8b2f50690e88d66cceccb250f5f432d057b529ff078396a577ecb59cd088ebe5` |
| REA TXM Mach-O inspection | `ev_4b8e5605b1061cc3e3c6f6a17c18f5a62379a07684ac89d44573706dd66d4629` |

`absolute-boot-*` identities belong to this project's format inspector; they are
not REA Evidence IDs. All other artifact hashes, payload offsets, sizes, version
declarations and source-to-boot payload matches are in the JSON ledger. The public
ledger also hashes the complete local record.

REA's firmware-region operation was unavailable on this macOS host: its adapter
requires Linux and a caller-supplied absolute `REA_BINWALK_COMMAND`. That diagnostic
is retained at `research/local/boot-firmware/rea-firmware-provider-unavailable.json`.
The Image4/LZFSE/ADT work above uses the project's parser and Apple's installed
Compression framework, and is labeled accordingly.

Fourteen validation checks passed, including malformed DER/Mach-O rejection,
complete ADT consumption, unique kernelcache member identities, all three REA
records, payload matching, and absence of volume UUIDs in the public ledger.
The validation record is `research/local/boot-firmware/validation.json`.

```sh
PYTHONDONTWRITEBYTECODE=1 python3 script/research_boot_firmware.py --rea
```

The command reuses matching REA records and preserves earlier local captures.
Raw captures and the two decoded monitor images remain in the gitignored local
research directory. Personalized manifests and keybags are skipped, and volume
identifiers are replaced with placeholders before recording paths.
