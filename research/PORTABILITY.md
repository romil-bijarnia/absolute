# Shared core verification — 2026-10-14

This is the initial Preview 0.2 portability record. Current regression results
are recorded in [SYSTEM-COVERAGE.md](SYSTEM-COVERAGE.md).

`AbsoluteCore` and the `absolute` command-line host compiled and executed on both
systems below. Each run passed 12 behavior tests and seven integration checks.
These are runtime observations from this project, separate from REA's static
inspection of Apple's shipped applications.

| Host | Toolchain | Architecture | Result |
| --- | --- | --- | --- |
| macOS 27.0, build 26A5421a | Apple Swift 6.4, Xcode beta | arm64 | 12 tests and seven integration checks passed |
| Ubuntu 24.04.5 LTS in Lima | Swift 6.2.4, official Ubuntu 24.04 container | aarch64 | 12 tests and seven integration checks passed |

The integration checks read a real project directory, fetch file information,
resolve a file's parent for reveal, read a text preview, serialize and restore a
desktop session through disk, restore a minimized window, and reject a stale
save. Session tests additionally verify per-window preferences, geometry and
order, corrupt-file preservation, schema validation, and browser/window
consistency. File-service tests cover fresh metadata, symbolic-link identity,
missing files, and rejection of remote URLs.

Complete machine-local reports:

- [macOS core report](local/macos-core-report.json)
- [Linux core report](local/linux-core-report.json)

The local directory is ignored by Git. Reproduce those reports using:

```sh
./script/check_core.sh
./script/check_linux.sh
```

## Native desktop and process restart

The final native run passed all 26 desktop checks and seven fresh-process
restoration checks. Both processes launched in the background, kept application
activation off, and quit after writing their reports:

- [Desktop checks](local/ui-check-20261014-145955/results.json)
- [Fresh-process restoration](local/ui-check-20261014-145955/restore-results.json)
- [File information panel](local/ui-check-20261014-145955/04-file-info.png)
- [Restored desktop](local/ui-check-20261014-145955/05-session-restored.png)

The restart check compares saved window geometry, order and minimization,
per-window folders and display preferences, and a wallpaper change left for the
normal quit handler to flush. The fresh process restored all of them.

Background mode verifies Get Info's shortcut registration and invokes its action
directly, because the application has no focused scene while inactive.
Foreground Get Info shortcut activation and external application launching were
not exercised in this run. Screenshots capture only our own window content.

## Linux environment

The Linux workflow uses the project-owned Lima VM `absolute-dev`, the VZ backend,
Ubuntu 24.04, two CPUs, 4 GB RAM, and a 16 GB sparse disk. Only this project is
mounted writable from the host. Container builds use the separate
`absolute-swift-build` volume and do not reuse macOS build outputs.

Pinned container:

```text
docker.io/library/swift:6.2-noble@sha256:eccc7a97f9b9881d9659e2e788081fd7675f86d39793b51200bfb178398b3784
```

The Linux verification exercises the shared model and filesystem services. Its
command-line host returns structured JSON; it does not render a graphical
desktop. The current graphical host uses macOS SwiftUI and AppKit. Linux
rendering, compositor integration, login/session services, boot-image assembly,
hardware drivers, and Mac application binary compatibility remain future work.
