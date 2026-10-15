# Absolute on Fedora

Absolute's desktop runs on Fedora KDE Plasma 6 (Fedora 44, Plasma 6.7 at the
time of writing), on the physical Mac's Fedora Asahi installation or inside
the virtual machine that `script/vm_fedora.sh` builds on the Mac.

## The surface installer

```sh
bash script/absolute_surface.sh --all            # packages, themes, profile, apply, login screen
bash script/absolute_surface.sh --check          # what is installed and active
bash script/absolute_surface.sh --restore DIR    # undo an --apply from its backup
```

`--all` does, in order:

1. `sudo dnf install` of the Plasma desktop, the applications in the Dock,
   Inter, JetBrains Mono, Kvantum, git, numpy and Pillow. Installed packages
   are skipped.
2. Fetches WhiteSur (KDE theme, icons, cursors, GTK theme) from GitHub at the
   commits pinned in `linux/fedora/plasma/profile.json` into
   `~/.cache/absolute/whitesur` and installs them for the current user.
3. Renders the wallpaper and installs the `org.absolute.desktop` profile and
   the Konsole profile into the user's data directory.
4. Backs up the Plasma preferences, applies the profile with
   `plasma-apply-lookandfeel --resetLayout`, writes the KWin, font, search,
   notification, lock-screen and Konsole settings, and sets the shortcuts
   through the global shortcut service (KWin hosts it in Plasma 6.7 and
   overwrites file edits).
5. With sudo available, sets up the login screen. Fedora 44 uses Plasma Login
   Manager: its wallpaper is set in `/etc/plasmalogin.conf`, and the WhiteSur
   colours, icons and cursors plus the display scale are copied for its
   greeter user. Older Fedora with SDDM gets WhiteSur's SDDM theme.

Sign out and back in once after `--apply` so every application picks up the
fonts and theme.

`--mac-keys` adds the Mac keyboard: Toshy (pinned commit) remaps per
application, so Cmd+C/V/X/Z/A, Cmd+Q, Cmd+W, Cmd+T, Cmd+Tab and Cmd+Space do
what they do on a Mac in every app, with Cmd+C copying in the terminal while
Ctrl+C still interrupts. The keyboard reaches a virtual machine as "QEMU Virtio
Keyboard" and the Mac as its internal keyboard; both are declared Apple layouts
in Toshy's config. Because physical Ctrl then reaches KWin as Meta, Overview is
bound to both Ctrl+Up and Meta+Up and App Exposé to Ctrl+Down and Meta+Down.
Needs one sign-out; Toshy's tray icon is hidden to keep the menu bar clean.

## The virtual machine

`script/vm_fedora.sh` builds a Fedora 44 aarch64 machine with Homebrew's QEMU
and the Hypervisor framework, from Fedora's cloud image and a cloud-init seed:

```sh
bash script/vm_fedora.sh create            # download, verify, disk, SSH key, seed
bash script/vm_fedora.sh start --window    # boot with a window on the Mac (omit for headless)
bash script/vm_fedora.sh ssh               # shell inside
bash script/vm_fedora.sh shot NAME         # PNG of the machine's display
bash script/vm_fedora.sh stop
```

The machine lives under `~/.local/share/absolute/vm`. Its user is `romil`
(password `absolute`), signs in automatically, and runs at 3456x2160 with
2x scaling. Homebrew's QEMU has no virgl, so under `start --window` the
desktop is software rendered and animations crawl. For smooth animations run
it under UTM (`brew install --cask utm`, free):

```sh
bash script/vm_fedora.sh utm          # once: wraps the disk in Absolute.utm with virtio-gpu-gl
open ~/.local/share/absolute/vm/Absolute.utm
```

After the first sign-in under UTM, run `bash script/vm_fedora.sh display` once:
KWin otherwise takes QEMU's 1280x800 as the preferred mode, which at 2x is a
640x400-point desktop. The command selects the 3456x2160 mode (added by a
kernel parameter from the seed), so UTM's full screen shows the desktop pixel
for pixel, and copies the choice to the login screen.

UTM is sandboxed, so the disk and its base image move inside the bundle; the
script keeps using that disk, reaches the machine through UTM's shared network
(the address leased to the machine's MAC) and refuses to start its own QEMU
while UTM has the machine running. The surface was built and checked in this
machine: `push` the checkout in and run the installer over `ssh`.

## The native preview application

`script/install_fedora.sh --install` builds the Swift/GTK preview
(`AbsoluteLinux`) for the physical Fedora installation; its `--apply-desktop`
now delegates to the surface installer above.
