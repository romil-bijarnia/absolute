# Absolute project

The goal is an open-source desktop developed on the user's Mac, followed by a
bootable system. Desktop Preview 0.3 has native macOS and GTK Linux hosts,
saved sessions, file services, and a verified portable command-line host.
The next milestone is a self-contained bootable VM image and compositor/session
integration. The Linux host currently manages only its own Files windows.
Preserve this objective when resuming a thread.

- Keep `AbsoluteCore` free of AppKit and SwiftUI; platform work belongs in the desktop host.
- Use `script/build_and_run.sh` for builds, launches, core tests, and the native self-check.
- Use `script/check_core.sh` for portable checks and `script/check_linux.sh` for the project-owned Linux VM.
- Use `script/run_linux.sh` to run, build, check, or stop the Linux desktop. Its separate Swift package under `linux/` owns GTK and GIO dependencies.
- Run native checks with `--background` when working unattended; they use isolated session state and quit automatically.
- Use the installed Node runtime and REA package under `tools/`; do not register global MCP integrations as part of research.
- Keep complete machine-local captures under gitignored `research/local/`; record concise findings and evidence identities in `research/FINDINGS.md`.
- Distinguish artifact observations, static inferences, runtime observations, and implementation choices.
- REA research currently covers initial static Dock/Finder inspections only. Do not describe macOS reverse engineering as complete.
- Do not change the installed operating-system components to develop the prototype.
- Verify functional flows after related changes. Do not claim a standalone OS or Mac binary compatibility has been implemented. Platform rendering claims require evidence from the corresponding host.
- The user prefers direct action and concise progress updates. Avoid repeated permission questions for authorized work; follow the active tool runtime's permission policy.
