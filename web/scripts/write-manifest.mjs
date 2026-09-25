#!/usr/bin/env node
// Writes (or with --check verifies) dist/imd-deployment.json after `vite build`.
//
// Inputs (never hand-edited):
//   - the workflow deployment handoff (.imd/reads/deployment.json when present, otherwise the exact copy
//     committed at web/deployment/handoff.deployment.json; when both exist they must be byte-identical)
//   - the vetted network table (.imd/reads/network.json / web/deployment/handoff.network.json), whose
//     `network` object is copied unchanged into the manifest
//   - the implementation-derived ABIs exported into dist/abi/<Contract>.json by the build (from
//     web/public/abi, copied byte for byte from docs/abi at the pinned source commit)
//
// The manifest is the app's runtime deployment configuration. Every other exported file is listed with its
// SHA-256 (lowercase hex). The manifest excludes itself. ABI hashes are canonical keccak256 of the ABI JSON
// (sorted keys, no whitespace) and must equal the handoff's abiHash.
import { createHash } from 'node:crypto';
import { readFileSync, writeFileSync, readdirSync, statSync, existsSync } from 'node:fs';
import { join, relative, resolve, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';
import { keccak256, toBytes } from 'viem';

const here = dirname(fileURLToPath(import.meta.url));
const webRoot = resolve(here, '..');
const repoRoot = resolve(webRoot, '..');
const distDir = resolve(repoRoot, 'dist');
const check = process.argv.includes('--check');

const MAX_ASSETS = 128;
const MAX_FILE_BYTES = 8 * 1024 * 1024;
const EXPORT_BUDGET_BYTES = 24 * 1024 * 1024; // well under half of the checker's 64 MiB body budget

function fail(msg) {
  console.error(`manifest: ${msg}`);
  process.exit(1);
}

function readHandoff(name) {
  const pinned = resolve(repoRoot, '.imd/reads', name);
  const committed = resolve(webRoot, 'deployment', `handoff.${name}`);
  const havePinned = existsSync(pinned);
  const haveCommitted = existsSync(committed);
  if (!havePinned && !haveCommitted) fail(`neither ${pinned} nor ${committed} exists`);
  if (havePinned && haveCommitted) {
    const a = readFileSync(pinned);
    const b = readFileSync(committed);
    if (!a.equals(b)) fail(`${committed} differs from the pinned handoff ${pinned}; copy it byte for byte`);
  }
  return JSON.parse(readFileSync(havePinned ? pinned : committed, 'utf8'));
}

// Canonical JSON: object keys sorted recursively, no insignificant whitespace (matches the handoff's
// canonicalKeccak(abi)).
export function canonicalJson(value) {
  if (Array.isArray(value)) return `[${value.map(canonicalJson).join(',')}]`;
  if (value && typeof value === 'object') {
    return `{${Object.keys(value)
      .sort()
      .map((k) => `${JSON.stringify(k)}:${canonicalJson(value[k])}`)
      .join(',')}}`;
  }
  return JSON.stringify(value);
}

export function canonicalKeccak(value) {
  return keccak256(toBytes(canonicalJson(value))).slice(2);
}

function sha256Hex(buf) {
  return createHash('sha256').update(buf).digest('hex');
}

function walk(dir) {
  const out = [];
  for (const entry of readdirSync(dir)) {
    const full = join(dir, entry);
    const st = statSync(full);
    if (st.isDirectory()) out.push(...walk(full));
    else out.push(full);
  }
  return out;
}

const deployment = readHandoff('deployment.json');
const networkFile = readHandoff('network.json');

if (!existsSync(join(distDir, 'index.html'))) fail('dist/index.html missing; run `vite build` first');
if (deployment.version !== 1) fail(`unexpected handoff version ${deployment.version}`);
if (networkFile.network?.chainId !== deployment.chainId) fail('network.json chainId differs from handoff');

const contracts = deployment.contracts.map((c) => {
  const abiPath = `abi/${c.name}.json`;
  const abiFile = join(distDir, abiPath);
  if (!existsSync(abiFile)) fail(`${abiPath} missing from dist/ (expected export of docs/abi/${c.name}.json)`);
  const abiRaw = readFileSync(abiFile, 'utf8');
  const abi = JSON.parse(abiRaw);
  if (!Array.isArray(abi)) fail(`${abiPath} is not a raw ABI array`);
  const hash = canonicalKeccak(abi);
  if (hash !== c.abiHash) fail(`${abiPath} canonical keccak ${hash} != handoff abiHash ${c.abiHash}`);
  // The source-of-truth ABI at docs/abi must be byte-identical to the exported copy when it exists.
  const docsAbi = resolve(repoRoot, 'docs/abi', `${c.name}.json`);
  if (existsSync(docsAbi) && !readFileSync(docsAbi).equals(readFileSync(abiFile))) {
    fail(`${abiPath} differs from docs/abi/${c.name}.json`);
  }
  if (!/^0x[0-9a-f]{40}$/.test(c.address)) fail(`${c.name} address is not lowercase hex: ${c.address}`);
  return { name: c.name, address: c.address, abiHash: c.abiHash, abiPath };
});

const files = walk(distDir)
  .map((f) => relative(distDir, f).split('\\').join('/'))
  .filter((p) => p !== 'imd-deployment.json')
  .sort();

if (files.length > MAX_ASSETS) fail(`${files.length} assets exceed the limit of ${MAX_ASSETS}`);
let total = 0;
const assets = files.map((path) => {
  const buf = readFileSync(join(distDir, path));
  if (buf.length > MAX_FILE_BYTES) fail(`${path} is ${buf.length} bytes (> 8 MiB)`);
  total += buf.length;
  return { path, sha256: sha256Hex(buf) };
});
if (total > EXPORT_BUDGET_BYTES) fail(`export totals ${total} bytes, over the ${EXPORT_BUDGET_BYTES} budget`);
if (!assets.some((a) => a.path === 'index.html')) fail('index.html not enumerated');
for (const c of contracts) if (!assets.some((a) => a.path === c.abiPath)) fail(`${c.abiPath} not enumerated`);

const manifest = {
  version: 1,
  launchId: deployment.launchId,
  chainId: deployment.chainId,
  sourceCommit: deployment.sourceCommit,
  attestationHash: deployment.attestationHash,
  contracts,
  assets,
  network: networkFile.network,
};

const out = `${JSON.stringify(manifest, null, 2)}\n`;
const target = join(distDir, 'imd-deployment.json');

if (check) {
  if (!existsSync(target)) fail('dist/imd-deployment.json missing');
  const current = readFileSync(target, 'utf8');
  if (current !== out) {
    fail('dist/imd-deployment.json is stale; run `npm run manifest` after the build');
  }
  console.log(
    `manifest: OK (${assets.length} assets, ${total} bytes, ${contracts.length} contracts, chain ${manifest.chainId})`,
  );
} else {
  writeFileSync(target, out);
  console.log(
    `manifest: wrote dist/imd-deployment.json (${assets.length} assets, ${total} bytes, ${contracts.length} contracts)`,
  );
}
