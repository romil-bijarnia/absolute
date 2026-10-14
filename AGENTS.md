# Absolute project

The goal is an open-source desktop developed on the user's Mac, followed by a
bootable system. Desktop Preview 0.2 has a native host, saved sessions, file
services, and a verified Linux command-line host. The next milestone is Linux
graphical rendering using the same core.
Preserve this objective when resuming a thread.

- Keep `AbsoluteCore` free of AppKit and SwiftUI; platform work belongs in the desktop host.
- Use `script/build_and_run.sh` for builds, launches, core tests, and the native self-check.
- Use `script/check_core.sh` for portable checks and `script/check_linux.sh` for the project-owned Linux VM.
- Run native checks with `--background` when working unattended; they use isolated session state and quit automatically.
- Use the installed Node runtime and REA package under `tools/`; do not register global MCP integrations as part of research.
- Keep complete machine-local captures under gitignored `research/local/`; record concise findings and evidence identities in `research/FINDINGS.md`.
- Distinguish artifact observations, static inferences, runtime observations, and implementation choices.
- Do not change the installed operating-system components to develop the prototype.
- Verify functional flows after related changes. Do not claim a standalone OS, another-platform renderer, or Mac binary compatibility has been implemented by this desktop host.
- The user prefers direct action and concise progress updates. Avoid repeated permission questions for authorized work; follow the active tool runtime's permission policy.
