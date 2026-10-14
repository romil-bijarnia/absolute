# Native macOS file semantics

This pass analyzes actual machine code in the installed `/usr/bin/readlink` and
`/usr/bin/stat`, then checks their behavior in isolated fixtures. It covers one
small filesystem utility boundary on macOS 27.0, build 26A5421a. Six native
function dossiers and 73 runtime cases are available; macOS as a whole remains
largely unexplored.

## Artifact and analysis boundary

The two installed paths have the same device, inode, and SHA-256 identity:
`aed132b62730b52035afddefc1b0b5b48beba1e7da3dfdc1afa00cd9273c984b`.
A local arm64e slice produced by `lipo -thin arm64e` has SHA-256
`acbb9c11bb1be09052233bf7cd7b93f7a823a714b296d1a7a6e4789d826060e7`.
Only the installed system commands were executed; the extracted slice was used
for static analysis. REA 6.4.0 and Ghidra 12.1.3 supplied disassembly, recovered
pseudocode, and static call references.

The entry at `0x1000005e8` compares the invocation name with `readlink` and chooses
its option and output behavior. Both names share a formatter at `0x10000099c`
and field rendering at `0x100000f18`. That latter function calls imported
`readlink` at `0x1000012f0` and imported `realpath$DARWIN_EXTSN` at `0x100001390`.
The default metadata path calls imported `lstat` at `0x1000008dc`; the `-L` path
calls `stat` at `0x10000089c` and conditionally falls back through `lstat` at
`0x1000008c0`.

These are static observations of the utility and its library boundaries. The
library implementations and kernel filesystem code were not recovered here.
Recovered types are approximate. Ghidra reports unsettled type propagation in
the field renderer, and two small error helpers show misleading fallthrough
past terminal error calls. Those helper pseudocode tails are not treated as
faithful behavior. The contracts below use corroborating execution results.

## Observed behavior

Runtime probes create ordinary files, directories, relative and absolute links,
link chains, dangling links, a two-link loop, and non-directory targets inside
`research/local/native-code/`. Standard output, standard error, and exit status
are recorded independently. `<fixture>` below stands for that private directory.

| Input and operation | Observed result |
| --- | --- |
| Raw `readlink` on a dangling link to `missing.txt` | Prints `missing.txt`; exits 0. |
| Raw `readlink` on a chain or loop | Prints the immediate stored destination; exits 0. |
| Raw `readlink` on an ordinary file | No output; exits 1. |
| `stat` on a link | Describes the link entry and its stored target. |
| `stat -L` on a valid link | Describes the target. |
| `stat -L` on a dangling link | Falls back to the link entry; exits 0. |
| `stat -L` on a loop or a target containing a non-directory component | Fails with the corresponding error; exits 1. |
| `readlink -f` on a dangling link | Prints `<fixture>/missing.txt` but exits 1. |
| `readlink -f` on a loop or missing parent | May print a partial absolute path but exits 1. |
| `readlink -f` on a nonexistent input entry | No output; exits 1. |
| `nested-link/../child.txt`, with the link targeting `target-dir/nested` | Resolves to `target-dir/child.txt`, after following the link. |
| Metadata for `directory-link/` | Describes the directory; the trailing slash matters. |
| Mixed valid/non-link operands | Successful outputs remain visible; aggregate exit status is 1. |

The native entry checks `ENOENT` before the `stat -L` fallback. The runtime
probes distinguish that behavior from `ENOTDIR` and `ELOOP`. The canonical-path
formatter stores failure separately from its output buffer, explaining why a
printed path does not establish successful resolution.

## Contract implemented in Absolute

`LocalFileService` now obtains entry metadata without requiring a link's target
to exist. Listing, information, and reveal preserve the requested entry path;
the stored link destination remains available for dangling links and loops.

The new `resolve(_:policy:)` operation distinguishes `.noFollow` from `.follow`.
No-follow inspects the final entry and returns `.notFollowed`. Follow performs
filesystem path resolution and returns `.resolved` with a `resolvedURL` only
when it succeeds. Missing entries or targets, non-directory components, loops,
and access failures have separate statuses and available POSIX error codes.
Both results retain the requested `entryURL`; a link's stored destination is a
separate field.

An explicit trailing slash retains its requirement that the final component
name a directory. Both policies reject an ordinary `file/` or a dangling `link/`;
a valid directory link with a slash is inspected as the directory. The same rule
applies to information and reveal. Link URLs without that requirement retain
ordinary link-entry metadata. Foundation strips the slash from both `path` and
`withUnsafeFileSystemRepresentation`, so the service preserves the URL's
`hasDirectoryPath` flag when constructing a filesystem path. The CLI also
preserves this flag across NSString tilde expansion, which removes trailing
slashes from its returned string.

This is an original API choice informed by the observed behavior. A failed
Absolute resolution never presents a partial buffer as a successful target.
Strict follow reports a missing target instead of adopting `stat -L`'s fallback
as successful target resolution. Entry inspection remains available separately.
This is not a claim of byte-for-byte CLI or Finder compatibility.

The meaning of `symlink/..` paths now survives CLI argument parsing, Linux `--project`
parsing, navigation history, browser snapshots, and supplied desktop state-file
locations. These callers retain parent components until the filesystem traverses
them. Session schema 1 is unchanged. A state-file path containing `alias/..`
is read and atomically saved at the filesystem-selected parent; an unrelated
file at the lexically collapsed path stays untouched. Concurrent path replacement,
very long links, and unusual non-UTF-8 filenames remain untested.

## Evidence and verification

Complete local artifacts are ignored by Git. Public identities, function
ranges, call targets, selected normalized outputs, observation classifications,
and remaining unknowns are in [native-code-findings.json](native-code-findings.json).
No recovered function bodies or system binaries are included in the public report.

| Recovered function entry | Canonical REA Evidence ID |
| --- | --- |
| `0x1000005e8` | `ev_2b5dff74dff188d7a6e3a5ab58c866f345fd4680d8aa72541326627f288df503` |
| `0x10000099c` | `ev_b65cc55115143cf9af16656f0848cf4a2cb8c21de71a32e8d2a583c9d1d859b5` |
| `0x100001a30` | `ev_bc0d3d67eff8e6e8d541b4a5358ddcd5f7e65e8ded36170735e11ca4be351b42` |
| `0x100000f18` | `ev_f87e16e04ccc925de0ea2446d89ecfe56983a594131a7be779f0ecf55faa5979` |
| `0x100000ed4` | `ev_e4ab2ebb1739c70c204bcfdaecfc9e6bee8c8b6a28521e3c3b786525c1466834` |
| `0x100001a74` | `ev_5e5ba7e6220496d6b97b2a34c758ef1200a9184d21175a1e609bf8ba3c1717b3` |

The runtime record is identified by its SHA-256 rather than a REA Evidence ID,
because those observations were captured with direct subprocess execution.

- `swift test --jobs 2 --filter FileServiceTests`: all 11 tests pass on macOS.
- `./script/check_core.sh`: all 22 unit tests and all 15 CLI integration checks pass on macOS.
- `python3 script/research_native_code.py`: reuses the six retained native dossiers and captures 73 independent runtime cases.

The focused tests cover dangling-link listing/information/reveal, directory-link
identity, successful resolution, chain and parent traversal, loop versus
non-directory errors, non-local URL rejection, and protocol dispatch. Two additional unit tests exercise real filesystem reads
through navigation history and saved browser state, plus state-file writes with
a decoy at the wrongly collapsed path. The CLI verifier launches actual `info`,
`ls`, `reveal`, and `session` child commands with the same counterexample, so
argument parsing and JSON serialization participate in the checks. Three further
unit tests cover files, directory links, and dangling links with a trailing slash
under both policies. Actual CLI information/reveal commands check the same
requirements; all 12 cases in `research/local/native-code/trailing-slash-cli.json`
pass. Directory
metadata sizes and timestamps depend on the fixture filesystem and are not
hard-coded as portable expectations.

To reproduce, run `python3 script/research_native_code.py` from the repository
root with the pinned tools installed. Set `GHIDRA_INSTALL_DIR` and `JAVA_HOME`
for a different existing tool installation. `--runtime-only` runs only the
isolated fixtures; `--refresh` archives retained analysis before another native
pass. If the installed binary changes, select a new `--output` directory under
`research/local/` so identities cannot be silently mixed.
