#!/usr/bin/env node
// Static REA inspection only. Does not launch or modify either system app.
import { execFile } from 'node:child_process';
import { createHash } from 'node:crypto';
import { mkdir, readFile, readdir, rename, writeFile } from 'node:fs/promises';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { promisify } from 'node:util';

const run = promisify(execFile);
const project = path.dirname(path.dirname(fileURLToPath(import.meta.url)));
const cli = path.join(project, 'tools/node_modules/rea-agents/scripts/rea.mjs');
const destination = path.join(project, 'research/local');
await mkdir(destination, { recursive: true });
const commands = [
  'inspect-artifact', 'inspect-plist', 'inspect-macho', 'trace-dylib-resolution',
];
const targets = ['Dock', 'Finder'].map(name => ({
  name,
  target: `/System/Library/CoreServices/${name}.app`,
}));
const results = [];
let previous = { results: [] };
try {
  previous = JSON.parse(await readFile(path.join(destination, 'capture-manifest.json'), 'utf8'));
} catch {}
const host = await run('/usr/bin/sw_vers', [], { timeout: 10_000 });
const refresh = process.argv.includes('--refresh') || previous.host !== host.stdout.trim();

// Independent targets run concurrently; each target's records remain ordered.
await Promise.all(targets.map(async ({ name, target }) => {
  for (const command of commands) {
    const args = [cli, command, target, '--format', 'json', '--full-output'];
    const base = `${name.toLowerCase()}-${command}`;
    // Reuse complete canonical Evidence from a prior successful inspection.
    try {
      const saved = await readFile(path.join(destination, `${base}.json`), 'utf8');
      const parsed = JSON.parse(saved);
      if (parsed.data?.evidence_id && !parsed.data?.error) {
        if (!refresh) {
          const prior = previous.results.find(item => item.target === target && item.command === command);
          results.push({
            ...prior, target, command, arguments: args.slice(1), exitCode: 0,
            canonical: true, evidenceId: parsed.data.evidence_id,
            outputFile: `${base}.json`, bytes: Buffer.byteLength(saved),
            sha256: createHash('sha256').update(saved).digest('hex'),
          });
          process.stdout.write(`${name} ${command}: reused complete Evidence\n`);
          continue;
        }
        await writeFile(path.join(destination, `${base}.previous-${Date.now()}.json`), saved);
      } else {
        await writeFile(path.join(destination, `${base}.failed-${Date.now()}.json`), saved);
      }
    } catch {}
    const started = new Date().toISOString();
    let stdout = '', stderr = '', exitCode = 0;
    try {
      const result = await run(process.execPath, args, {
        cwd: project,
        maxBuffer: 128 * 1024 * 1024,
        timeout: 180_000,
      });
      ({ stdout, stderr } = result);
    } catch (error) {
      stdout = error.stdout ?? '';
      stderr = error.stderr ?? error.message;
      exitCode = error.code ?? 'unknown';
    }
    let canonical = false;
    let evidenceId = null;
    try {
      const envelope = JSON.parse(stdout);
      canonical = true;
      evidenceId = envelope.data?.evidence_id ?? envelope.evidence_id ?? envelope.result?.evidence_id ?? null;
    } catch {}
    const outputFile = `${base}.${canonical ? 'json' : 'stdout.log'}`;
    const partial = path.join(destination, `${outputFile}.partial`);
    await writeFile(partial, stdout);
    await rename(partial, path.join(destination, outputFile));
    if (stderr) await writeFile(path.join(destination, `${base}.stderr.log`), stderr);
    const record = {
      target, command, arguments: args.slice(1),
      started, finished: new Date().toISOString(), exitCode, canonical,
      evidenceId, outputFile, bytes: Buffer.byteLength(stdout),
      sha256: createHash('sha256').update(stdout).digest('hex'),
    };
    results.push(record);
    process.stdout.write(`${name} ${command}: exit=${exitCode}, json=${canonical}, bytes=${record.bytes}\n`);
  }
}));
const version = await run(process.execPath, [cli, '--version'], { timeout: 10_000 });
const manifest = {
  schema: 1,
  scope: 'Static bundle, plist, Mach-O, and dylib resolution; no target execution.',
  host: host.stdout.trim(),
  rea: version.stdout.trim(),
  results: results.sort((a, b) => a.target.localeCompare(b.target) || a.command.localeCompare(b.command)),
};
await writeFile(path.join(destination, 'capture-manifest.json'), `${JSON.stringify(manifest, null, 2)}\n`);
if (results.some(item => item.exitCode !== 0 || !item.evidenceId)) {
  process.exitCode = 1;
} else {
  const findings = {
    schema: 1,
    evidenceType: 'static-observation',
    host: Object.fromEntries(host.stdout.trim().split('\n').map(line => {
      const index = line.indexOf(':');
      return [line.slice(0, index), line.slice(index + 1).trim()];
    })),
    rea: version.stdout.trim(),
    applications: [],
    inference: 'The desktop depends on services outside the two app bundles. Rebuilding their observable behavior requires separate replacements for those service boundaries.',
    limitations: [
      'This capture inventories files and parses static declarations. It does not observe app execution or recover original source.',
      'Outside-target and undetermined dependencies are not evidence of missing libraries. System libraries may be supplied by the dyld shared cache.',
      'Names of nested executables establish inventory, not which processes run or their behavior.',
      'Mach-O import/export symbol inventories may omit stripped or toolchain-hidden symbols.',
      'No window-server, driver, boot, kernel, or runtime behavior was analyzed.',
    ],
  };
  for (const { name, target } of targets) {
    const load = async command => JSON.parse(await readFile(path.join(destination, `${name.toLowerCase()}-${command}.json`), 'utf8')).data;
    const [artifact, plist, macho, trace] = await Promise.all(commands.map(load));
    const inventory = artifact.normalized_result.substeps.find(step => step.operation === 'inventory_artifact').evidence;
    const i = inventory.normalized_result;
    const p = plist.normalized_result;
    const m = macho.normalized_result;
    const t = trace.normalized_result;
    const mainImage = `Contents/MacOS/${name}`;
    const main = t.images.find(image => image.path === mainImage);
    const mainLoads = t.edges.filter(edge => edge.loader === mainImage);
    const publicBoundaries = /\/(AppKit|Foundation|SwiftUI|SwiftUICore|FileProvider|CoreSpotlight|QuickLook|QuickLookUI|UniformTypeIdentifiers)\.framework\//;
    const serviceBoundaries = /\/(SkyLight|WindowManager|WindowManagement|DesktopServicesPriv|DesktopServicesUI|IconServices|RunningBoardServices)\.framework\//;
    findings.applications.push({
      name, target,
      evidence: [artifact, plist, macho, trace].map((item, index) => ({
        operation: item.operation, evidenceId: item.evidence_id,
        file: `local/${name.toLowerCase()}-${commands[index]}.json`,
      })),
      inventory: {
        evidenceId: inventory.evidence_id,
        manifestId: i.manifest.manifest_id,
        bundleSha256: i.manifest.root_sha256,
        uniqueContentNodes: i.manifest.node_count,
        pathOccurrences: i.manifest.occurrence_count,
        regularFileOccurrences: i.occurrences.filter(item => item.entry_kind === 'file').length,
      },
      declarations: {
        ...p.bundle,
        minimumSystemVersion: p.value.LSMinimumSystemVersion ?? null,
        agentUiElement: p.value.LSUIElement ?? null,
        principalClass: p.value.NSPrincipalClass ?? null,
        mainNib: p.value.NSMainNibFile ?? null,
        services: (p.value.NSServices ?? []).map(service => service.NSMessage),
        urlSchemes: (p.value.CFBundleURLTypes ?? []).flatMap(type => type.CFBundleURLSchemes),
      },
      mainExecutable: {
        path: main.path, sha256: main.sha256,
        bytes: main.slices.reduce((sum, slice) => sum + slice.slice_size, 0),
        architectures: m.architectures.items.map(item => item.name),
        build: m.build_metadata.items,
      },
      executableRoots: t.roots.map(root => ({ ...root })),
      dynamicBoundary: {
        totalDeclaredEdges: t.edges.length,
        mainDeclaredDylibEdges: mainLoads.length,
        weakDeclaredEdges: t.edges.filter(edge => edge.weak).length,
        resolutionStatuses: t.edges.reduce((counts, edge) => {
          counts[edge.resolution.status] = (counts[edge.resolution.status] ?? 0) + 1;
          return counts;
        }, {}),
        selectedPublicFrameworkLoads: mainLoads.filter(edge => publicBoundaries.test(edge.install_name)).map(edge => edge.install_name),
        selectedServiceFrameworkLoads: mainLoads.filter(edge => serviceBoundaries.test(edge.install_name)).map(edge => edge.install_name),
        coverage: t.coverage,
      },
    });
  }
  await writeFile(path.join(project, 'research/findings.json'), `${JSON.stringify(findings, null, 2)}\n`);
  const markdown = [
    '# Local macOS desktop evidence',
    '',
    'This report covers the initial Dock/Finder bundle pass. See [SYSTEM-COVERAGE.md](SYSTEM-COVERAGE.md) for the current system-wide investigation.',
    '',
    `REA ${findings.rea}; ${findings.host.ProductName} ${findings.host.ProductVersion}, build ${findings.host.BuildVersion}.`,
    'The targets were `/System/Library/CoreServices/Dock.app` and `/System/Library/CoreServices/Finder.app`.',
    'All eight static inspections completed. No target process was launched or modified.',
    '',
    '## Observations',
    '',
    '| Measured fact | Dock | Finder |',
    '| --- | --- | --- |',
    `| Bundle identifier | ${findings.applications[0].declarations.identifier} | ${findings.applications[1].declarations.identifier} |`,
    `| Bundle version | ${findings.applications[0].declarations.version} | ${findings.applications[1].declarations.version} |`,
    `| Regular-file path occurrences | ${findings.applications[0].inventory.regularFileOccurrences} | ${findings.applications[1].inventory.regularFileOccurrences} |`,
    `| Executable roots | ${findings.applications[0].executableRoots.length} | ${findings.applications[1].executableRoots.length} |`,
    `| Main-executable bytes | ${findings.applications[0].mainExecutable.bytes} | ${findings.applications[1].mainExecutable.bytes} |`,
    `| Main-executable architecture | ${findings.applications[0].mainExecutable.architectures.join(', ')} | ${findings.applications[1].mainExecutable.architectures.join(', ')} |`,
    `| Declared main-executable dylib loads | ${findings.applications[0].dynamicBoundary.mainDeclaredDylibEdges} | ${findings.applications[1].dynamicBoundary.mainDeclaredDylibEdges} |`,
    '',
    '`Dock.app/Contents/Info.plist` declares `LSUIElement = true`. Dock includes DockControls.appex and three XPC-service executables: DockHelper, com.apple.dock.external.extra.arm64, and com.apple.dock.extra.',
    '',
    '`Finder.app/Contents/Info.plist` declares the services `open`, `reveal`, and `showInfo`; the principal class is `TApplication` and the main nib is `Application`. Its bundle also contains FileSearch.appex and the AirDrop, All My Files, Computer, Network, Recents, and iCloud Drive executable roots. These declarations and names do not establish runtime behavior.',
    '',
    'Both main executables declare loads of SkyLight, DesktopServicesPriv, and IconServices. Dock also declares WindowManager, WindowManagement, and RunningBoardServices. Finder declares AppKit, SwiftUI, FileProvider, CoreSpotlight, and QuickLookUI. Exact paths and all executable SHA-256 identities are retained in [findings.json](findings.json).',
    '',
    `Across their executable roots, Dock has ${findings.applications[0].dynamicBoundary.totalDeclaredEdges} declared load edges and Finder has ${findings.applications[1].dynamicBoundary.totalDeclaredEdges}. Every one has resolution status \`undetermined\`: the candidates lie outside the selected bundles. This is a search boundary, not a finding that libraries are missing. System libraries may be supplied by the dyld shared cache.`,
    '',
    '## Evidence ledger',
    '',
    '| Target | Operation | Canonical Evidence ID |',
    '| --- | --- | --- |',
    ...findings.applications.flatMap(application => application.evidence.map(item => `| ${application.name} | ${item.operation} | \`${item.evidenceId}\` |`)),
    '',
    'The complete unfiltered CLI JSON records and a capture manifest with output hashes live in `research/local/`, which is ignored by Git.',
    (await readdir(destination)).some(file => file.includes('.failed-'))
      ? 'Initial failed plist/Mach-O envelopes are retained there as `*.failed-*.json`; they were cleanup failures caused by a sandbox-blocked process-table read and are not successful native observations. The successful retry records above are the evidence used here.'
      : '',
    '',
    '## Reconstruction implication',
    '',
    `**Inference:** ${findings.inference}`,
    '',
    '**Next component, design choice:** a file-service boundary for our Files app, using Finder’s declared `open`, `reveal`, and `showInfo` messages as investigation seeds. A reviewable first specification is: open a selected folder in the file browser; reveal a file by navigating to its parent and selecting it; show a read-only inspector with name, type, size, and modification time. Verify those results against a known temporary folder and metadata from the filesystem. Before claiming Finder compatibility, separately observe its actual inputs and outputs. Keep filesystem operations behind an interface so the desktop can later use another operating-system backend.',
    '',
    '**Answered:** exact bundle inventory, main-executable identity and architecture, parsed application declarations, and bounded dylib load declarations. **Unresolved:** process behavior, visual metrics, window-server behavior, private-service protocols, kernel, drivers, and boot sequence. No pseudocode or original source was recovered in this pass.',
    '',
    '## Reproduce',
    '',
    'From the project root after installing the pinned tools:',
    '',
    '```sh',
    'tools/node_modules/node/bin/node script/research_macos.mjs',
    '```',
    '',
    'By default the script reuses complete records captured on the same macOS build. Add `--refresh` to inspect again; earlier records are preserved. It also writes `findings.json` and this ledger from retained canonical Evidence. All target inspections are static.',
    '',
  ].join('\n');
  await writeFile(path.join(project, 'research/FINDINGS.md'), markdown);
  process.stdout.write('Wrote research/findings.json and research/FINDINGS.md from the complete retained Evidence.\n');
}
