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
(password `absolute`), signs in automatically, and runs at 2880x1800 with
2x scaling. Graphics are software rendered (Homebrew's QEMU has no virgl), so
animations are slower than on hardware. The surface was built and checked in
this machine: `push` the checkout in and run the installer over `ssh`.

## The native preview application

`script/install_fedora.sh --install` builds the Swift/GTK preview
(`AbsoluteLinux`) for the physical Fedora installation; its `--apply-desktop`
now delegates to the surface installer above.
