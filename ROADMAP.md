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

## Next: Linux graphical host

Use the verified Linux core to implement the host boundary for file opening,
application discovery, clipboard, icons, and graphical rendering.
The current SwiftUI renderer is a macOS development host and will need a
counterpart on the new platform.

First acceptance target: render the desktop and a Files window inside the Linux
VM; navigate real folders, reveal a file, display its information, and restore the
window and folder after a fresh launch using the existing core services.

Then add desktop file operations and checks for the Linux graphical host before
making it a complete desktop session.

## Bootable system

Package the desktop session with an existing open-source base. Add a compositor,
input and display handling, login/session management, settings, notifications,
installation, and updates. Verify the initial image in a VM before targeting
hardware.

Choose kernel and hardware targets using the working second host. Supporting
macOS application binaries requires a compatible loader, runtimes, frameworks,
and operating-system interfaces beyond the visible desktop.
