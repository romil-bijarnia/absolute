# Absolute project

The goal is an open-source macOS-compatible system developed from investigation
of the user's Mac. The requested scope includes the entire system, graphics,
boot, drivers and firmware. Desktop Preview 0.3 has native macOS and GTK Linux hosts,
saved sessions, file services, and a verified portable command-line host.
Current work expands system research and converts bounded behavioral findings
into verified Absolute implementations. The delivery target is the user's
existing Fedora/Asahi installation on the physical Mac, developed into a daily
macOS replacement with Absolute's desktop and compatibility components.
The Linux host currently manages only its own Files windows.
Preserve this objective when resuming a thread.

- The implementation strategy combines Fedora/Asahi reuse with macOS reverse engineering. Use Fedora for the operating-system base and Asahi's boot tooling, drivers, graphics and hardware research where supported; build Absolute's desktop and macOS-compatible interfaces above that foundation. Prefer upstream integration before writing a replacement.
- Interpret the full subsystem backlog as research, compatibility and integration scope. An unresolved subsystem does not automatically require a new kernel, driver, firmware image or service implementation. Keep firmware investigation in scope while reusing existing supported boot and device interfaces.
- The user explicitly rejected a VM deliverable. Do not create, provision or run VMs for this work unless the user later requests one. The existing Ubuntu preview is historical development evidence, not the next milestone. Inspect and build on the physical Fedora installation already present on the laptop.
- The physical target is Apple M3 Max, Mac15,10. Fedora Linux with KDE Plasma boot volumes, a Fedora EFI partition, an ext-family BOOT partition, a Btrfs partition and a Fedora 44 Asahi kernel were observed on the internal disk. Boot health and actual hardware behavior still require a session running in Fedora. Preserve upstream licenses and provenance when incorporating code or packages.
- The user authorizes using the installed Fedora and macOS files for this work. Inspect relevant system material and reuse suitable open-source components without repeated permission questions. Keep original Apple binaries and raw captures local as described below; public deliverables contain original implementations, observations and appropriately licensed source.
- Keep `AbsoluteCore` free of AppKit and SwiftUI; platform work belongs in the desktop host.
- `AbsoluteMach` is a portable in-process inline-message subset, not a system Mach IPC service or binary-compatibility layer. Keep its native C oracle independent of the Swift implementation; replay the frozen fixture on both hosts when behavior changes.
- Use `script/build_and_run.sh` for builds, launches, core tests, and the native self-check.
- Use `script/check_core.sh` for portable checks on the active operating system. `script/check_linux.sh` and `script/run_linux.sh` are legacy VM workflows and are not the native Fedora deployment path. The separate Swift package under `linux/` owns GTK and GIO dependencies.
- Native Fedora delivery uses `script/install_fedora.sh`, `script/check_fedora.sh`, and the Plasma profile in `linux/fedora/plasma/`. Reuse the installed Plasma/KWin Wayland session and real Fedora applications; the Swift/GTK desktop remains an optional development preview. Build a source archive with `python3 script/package_fedora.py`; keep its native-validation status explicit until checks run on the physical Fedora system.
- Run native checks with `--background` when working unattended; they use isolated session state and quit automatically.
- Use the installed Node runtime and REA package under `tools/`; do not register global MCP integrations as part of research.
- Keep complete machine-local captures under gitignored `research/local/`; record concise findings and evidence identities in `research/FINDINGS.md`.
- Distinguish artifact observations, static inferences, runtime observations, and implementation choices.
- Use `research/SYSTEM-COVERAGE.md` and `research/scope.json` as the current research index and open subsystem backlog. Initial Dock/Finder metadata is only one earlier capture.
- Full macOS reverse engineering remains incomplete. Function dossiers, export counts, artifact inventories, reference probes and compatible implementations are different coverage measures.
- Keep Apple binaries, full disassembly, decompiler output and machine-local raw captures in `research/local/`; public reports contain identities, original explanations and explicit limits.
- Run `python3 script/research_status.py` after updating research reports to refresh the index and verify linked evidence.
- Do not change the installed operating-system components to develop the prototype.
- Verify functional flows after related changes. Do not claim a standalone OS or Mac binary compatibility has been implemented. Platform rendering claims require evidence from the corresponding host.
- The user prefers direct action and concise progress updates. Avoid repeated permission questions for authorized work; follow the active tool runtime's permission policy.
- Never add AI-authorship statements, acknowledgements or co-author trailers to the user's work.
