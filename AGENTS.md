# Absolute project

The goal is an open-source macOS-compatible system developed from investigation
of the user's Mac. The requested scope includes the entire system, graphics,
boot, drivers and firmware. Desktop Preview 0.3 has native macOS and GTK Linux hosts,
saved sessions, file services, and a verified portable command-line host.
Current work expands system research and converts bounded behavioral findings
into verified Absolute implementations. A self-contained bootable VM image
and compositor/session integration remain implementation milestones.
The Linux host currently manages only its own Files windows.
Preserve this objective when resuming a thread.

- Keep `AbsoluteCore` free of AppKit and SwiftUI; platform work belongs in the desktop host.
- Use `script/build_and_run.sh` for builds, launches, core tests, and the native self-check.
- Use `script/check_core.sh` for portable checks and `script/check_linux.sh` for the project-owned Linux VM.
- Use `script/run_linux.sh` to run, build, check, or stop the Linux desktop. Its separate Swift package under `linux/` owns GTK and GIO dependencies.
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
