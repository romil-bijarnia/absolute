# Development sequence

## Completed: Desktop previews 0.1 and 0.2

Build the development host on the existing Mac. Keep desktop state, directory
navigation, file metadata, search ranking, and previews in `AbsoluteCore`.
Use the native host to iterate on actual interactions and collect screenshots.

The initial component is Files plus the Dock and app launcher. REA provides
artifact and dependency evidence from the installed system; our interface and
core behavior are implemented independently in this project.

Preview 0.2 adds the file-service boundary, reveal-and-select, a read-only file
inspector, and versioned desktop-session persistence. The session includes every
file window's folder, hidden-file setting, sort order, view mode, geometry,
minimization, and wallpaper. Native checks exercise the user flows and restart
the application to check the saved state.

The same core and command-line host have compiled and run on Ubuntu ARM64.
All 12 core tests and seven integration checks passed on macOS and Linux.
See [research/PORTABILITY.md](research/PORTABILITY.md).

## Behavior specifications

For each component, choose a bounded question, observe it, and write an
interaction contract with an executable check. Begin with Dock activation,
minimize/restore, keyboard launcher selection, folder navigation, and sorting.
Preserve OS build and artifact hashes with each research run.

Source code, static metadata, and runtime behavior answer different questions.
The findings ledger identifies which type of evidence supports each statement.

## Completed: Linux graphical host 0.3

The Linux host renders a native GTK 4 desktop and Files windows using the same
file services, navigation, search ranking, and versioned session model.
GIO supplies installed applications and native launch operations.

All 27 graphical integration checks passed: real folder navigation, search,
hidden files, views, information, reveal, text previews, dragging, resizing,
minimize/restore, launcher selection, wallpaper, and a full process restart.
See [research/LINUX-DESKTOP.md](research/LINUX-DESKTOP.md).

The development VM exposes its virtual display through a local browser viewer.
Window management currently covers the desktop's own Files windows.

## Next: Self-contained bootable system

Package the desktop with an existing open-source base and start it automatically
in a VM without mounting the Mac source directory. Add a compositor,
input and display handling, login/session management, settings, notifications,
desktop file operations, installation, and updates. Verify the initial image
and its external application windows in a VM before targeting hardware.

Choose kernel and hardware targets using the working second host. Supporting
macOS application binaries requires a compatible loader, runtimes, frameworks,
and operating-system interfaces beyond the visible desktop.
