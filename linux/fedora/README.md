# Absolute on native Fedora

This package targets the Fedora Asahi KDE installation already on the physical
Apple Silicon Mac. It adds an Absolute desktop profile using Plasma and KWin,
with real Fedora applications, plus the optional Swift/GTK development preview.

The profile uses an application menu bar, a centered floating Dock, Breeze Dark,
and an original ocean wallpaper. Dolphin provides file operations, Firefox web
browsing, Konsole a terminal, and Fedora's existing settings and services manage
the system. macOS application binary compatibility remains separate development
work.

## Install in Fedora

Open a terminal after booting Fedora and change into the extracted source folder:

```sh
bash script/install_fedora.sh --check
bash script/install_fedora.sh --install --apply-desktop
```

Run as the normal desktop user. The installer requests sudo only for missing
Fedora build packages, builds the Swift preview natively, and installs files in
the user's local application directories. It saves the previous KDE preferences
before applying the new panels and appearance. The backup location and restore
command are printed before the change.

To install the profile and preview without activating a new desktop layout:

```sh
bash script/install_fedora.sh --install
```

To install and apply only the native Plasma profile, without building the preview:

```sh
bash script/install_fedora.sh --apply-desktop
```

The profile activation changes the current panels and wallpaper. It does not
install another operating system or change partitioning, boot policy, the kernel,
or the display manager. Existing Asahi hardware support stays with Fedora's
packages.

## Verify on the physical Mac

```sh
bash script/check_fedora.sh
bash script/check_fedora.sh --json
bash script/check_core.sh
```

The readiness report records the active operating system, hardware identifiers,
desktop session, installed tools and observable device state. Device enumeration
alone does not verify physical input, audible playback, graphics correctness,
network connectivity, or suspend/resume. These need checks in the real session.
The core command runs the shared Swift tests and command-line integration checks.

The source package is marked `native-validation-pending` until installation,
desktop behavior and required hardware flows have been checked on Fedora.
Successful archive, syntax or macOS checks do not certify the Fedora desktop.

## Restore or remove

Use the backup directory printed during activation:

```sh
bash script/install_fedora.sh --restore-desktop /path/to/printed/backup
bash script/install_fedora.sh --uninstall
```

Uninstall preserves personal session data and preference backups. Restore the
previous desktop first when Absolute is the active profile.

## Source package

From the project checkout, create and verify a portable source archive:

```sh
python3 script/package_fedora.py
python3 script/package_fedora.py --verify dist/fedora/absolute-fedora-0.4.0-dev-source.tar.gz
```

`ABSOLUTE-RELEASE.json` records every included file's size, permissions and SHA-256.
The archive uses an explicit source allowlist. Machine-local research, extracted
Apple binaries, disk images, package caches and personal files are excluded.
Original Absolute code and artwork use the repository's MIT license. Fedora,
Asahi and KDE components retain their upstream licenses in the installed system.

See [the Plasma profile documentation](plasma/README.md) for its layout and the
upstream APIs used.
