import { readFileSync, existsSync } from 'node:fs';
import { resolve } from 'node:path';
import { describe, expect, it } from 'vitest';
import { keccak256, stringToBytes } from 'viem';
import { canonicalJson, canonicalKeccak, validateManifest, walletAddChainParams } from '../src/lib/deployment';
import { bytes16ToUuid, bytes32ToUuid, isCompleteUuid, uuidToBytes16 } from '../src/lib/uuid';
import { checkEvidenceUri, checkText, utf8ByteLength } from '../src/lib/uri';
import { describeAttestation, snapshotFromBytes, summarizeRequest } from '../src/lib/imdApi';
import { applyFilters, paginate } from '../src/components/DisputeList';
import { parseHash, serializeHash } from '../src/hooks/useHashState';
import { parseChainId, switchOrAddChain, type Eip1193Provider } from '../src/lib/wallet';
import { DEMO_DISPUTES } from '../src/lib/demo';

const root = resolve(__dirname, '..', '..');
const handoff = JSON.parse(readFileSync(resolve(root, 'web/deployment/handoff.deployment.json'), 'utf8'));
const networkFile = JSON.parse(readFileSync(resolve(root, 'web/deployment/handoff.network.json'), 'utf8'));

describe('deployment handoff and ABIs', () => {
  it('committed handoff copies are byte-identical to the pinned reads when those exist', () => {
    for (const name of ['deployment.json', 'network.json']) {
      const pinned = resolve(root, '.imd/reads', name);
      if (!existsSync(pinned)) continue;
      expect(readFileSync(pinned)).toEqual(readFileSync(resolve(root, 'web/deployment', `handoff.${name}`)));
    }
  });

  it('every ABI exported to public/abi has the canonical keccak the handoff attests', () => {
    for (const c of handoff.contracts) {
      const abi = JSON.parse(readFileSync(resolve(root, 'web/public/abi', `${c.name}.json`), 'utf8'));
      expect(Array.isArray(abi)).toBe(true);
      expect(canonicalKeccak(abi)).toBe(c.abiHash);
      // and is byte-identical to docs/abi at the pinned source commit
      expect(readFileSync(resolve(root, 'web/public/abi', `${c.name}.json`))).toEqual(readFileSync(resolve(root, 'docs/abi', `${c.name}.json`)));
    }
  });

  it('canonical JSON sorts keys recursively and strips whitespace', () => {
    expect(canonicalJson({ b: 1, a: [{ d: 2, c: 3 }], e: 'x' })).toBe('{"a":[{"c":3,"d":2}],"b":1,"e":"x"}');
    expect(canonicalKeccak([])).toBe(keccak256(stringToBytes('[]')).slice(2));
  });

  it('the built manifest (if present) matches the handoff and network block exactly', () => {
    const p = resolve(root, 'dist/imd-deployment.json');
    if (!existsSync(p)) return;
    const m = validateManifest(JSON.parse(readFileSync(p, 'utf8')));
    expect(m.launchId).toBe(handoff.launchId);
    expect(m.chainId).toBe(handoff.chainId);
    expect(m.sourceCommit).toBe(handoff.sourceCommit);
    expect(m.attestationHash).toBe(handoff.attestationHash);
    expect(m.contracts.map((c) => [c.name, c.address, c.abiHash])).toEqual(handoff.contracts.map((c: { name: string; address: string; abiHash: string }) => [c.name, c.address, c.abiHash]));
    expect(JSON.parse(readFileSync(p, 'utf8')).network).toEqual(networkFile.network);
    expect(m.assets.some((a) => a.path === 'index.html')).toBe(true);
    expect(m.assets.some((a) => a.path === 'imd-deployment.json')).toBe(false);
    for (const c of m.contracts) expect(m.assets.some((a) => a.path === c.abiPath)).toBe(true);
    for (const a of m.assets) expect(a.sha256).toMatch(/^[0-9a-f]{64}$/);
    expect(m.assets.length).toBeLessThanOrEqual(128);
  });

  it('validateManifest rejects traversal, URLs and mismatched chain ids', () => {
    const good = {
      version: 1,
      launchId: 'x',
      chainId: 11155111,
      sourceCommit: handoff.sourceCommit,
      attestationHash: handoff.attestationHash,
      contracts: [{ name: 'A', address: handoff.contracts[0].address, abiHash: handoff.contracts[0].abiHash, abiPath: 'abi/A.json' }],
      assets: [{ path: 'index.html', sha256: 'a'.repeat(64) }],
      network: networkFile.network,
    };
    expect(() => validateManifest(good)).not.toThrow();
    expect(() => validateManifest({ ...good, contracts: [{ ...good.contracts[0], abiPath: '../abi/A.json' }] })).toThrow(/abiPath/);
    expect(() => validateManifest({ ...good, contracts: [{ ...good.contracts[0], abiPath: 'https://x/abi.json' }] })).toThrow(/abiPath/);
    expect(() => validateManifest({ ...good, chainId: 1 })).toThrow(/chainId/);
    expect(() => validateManifest({ ...good, network: { ...good.network, rpcUrls: ['http://insecure'] } })).toThrow(/https/);
  });

  it('derives wallet_addEthereumChain params from the network block and matches the handoff walletAddChain', () => {
    expect(walletAddChainParams(networkFile.network)).toEqual(networkFile.walletAddChain);
  });
});

describe('uuid <-> bytes16', () => {
  it('encodes the documented example', () => {
    expect(uuidToBytes16('0192d5f8-a3b1-4c6e-9f2a-7b8c1d3e4f50')).toBe('0x0192d5f8a3b14c6e9f2a7b8c1d3e4f50');
    expect(bytes16ToUuid('0x0192d5f8a3b14c6e9f2a7b8c1d3e4f50')).toBe('0192d5f8-a3b1-4c6e-9f2a-7b8c1d3e4f50');
    expect(bytes32ToUuid('0x5e5ef975e1ff449d8bc14defee6b166700000000000000000000000000000000')).toBe('5e5ef975-e1ff-449d-8bc1-4defee6b1667');
  });
  it('rejects partial and zero UUIDs', () => {
    expect(isCompleteUuid('0192d5f8-a3b1')).toBe(false);
    expect(isCompleteUuid(' 0192D5F8-A3B1-4C6E-9F2A-7B8C1D3E4F50 ')).toBe(true);
    expect(() => uuidToBytes16('00000000-0000-0000-0000-000000000000')).toThrow(/zero/);
    expect(() => uuidToBytes16('nope')).toThrow();
  });
});

describe('evidence URI and text validation', () => {
  it('accepts https and ipfs, rejects everything else', () => {
    expect(checkEvidenceUri('https://example.org/a.pdf')).toMatchObject({ ok: true, kind: 'https' });
    expect(checkEvidenceUri('ipfs://bafybeigdyrzt5sfp7udm7hu76uh7y26nf3efuylqabf3oclgtqy55fbzdi/x.pdf')).toMatchObject({ ok: true, kind: 'ipfs' });
    expect((checkEvidenceUri('ipfs://bafybeigdyrzt5sfp7udm7hu76uh7y26nf3efuylqabf3oclgtqy55fbzdi') as { href: string }).href).toMatch(/^https:\/\/ipfs\.io\/ipfs\//);
    expect(checkEvidenceUri('javascript:alert(1)').ok).toBe(false);
    expect(checkEvidenceUri('http://example.org').ok).toBe(false);
    expect(checkEvidenceUri('data:text/html,hi').ok).toBe(false);
    expect(checkEvidenceUri('https://user:pw@example.org/').ok).toBe(false);
    expect(checkEvidenceUri('').ok).toBe(false);
    expect(checkEvidenceUri(`https://example.org/${'a'.repeat(600)}`).ok).toBe(false);
  });
  it('measures bytes, not characters', () => {
    expect(utf8ByteLength('é')).toBe(2);
    expect(checkText('a'.repeat(280), 280).ok).toBe(true);
    expect(checkText('é'.repeat(141), 280).ok).toBe(false);
    expect(checkText('', 280).ok).toBe(false);
  });
});

describe('IMD API parsing', () => {
  it('summarises a request and hashes attestation bytes exactly', () => {
    const s = summarizeRequest({ id: 'abc', question: 'q?', status: 'attested', chainId: 1, window: { fromBlock: 1, toBlock: 2, toBlockHash: '0x0' }, signer: '0xsig', computed: { answer: '1', figure: '4' } });
    expect(s.computedAnswer).toBe('1');
    expect(s.window?.toBlock).toBe(2);
    const bytes = new TextEncoder().encode('{"a": 1}\n');
    const snap = snapshotFromBytes(bytes, 'api');
    expect(snap.keccak).toBe(keccak256(bytes));
    // reformatting the JSON would change the hash: we commit to exact bytes
    expect(snap.keccak).not.toBe(keccak256(new TextEncoder().encode('{"a":1}')));
    expect(describeAttestation({ signer: '0x1', message: { answer: '0x01', fromBlock: 5, toBlock: 6 } })).toMatchObject({ signer: '0x1', answer: '0x01', fromBlock: 5 });
    expect(describeAttestation('garbage').signer).toBeNull();
  });
});

describe('filters, pagination, hash state', () => {
  it('filters by request, author, status', () => {
    expect(applyFilters(DEMO_DISPUTES, { request: '0192d5f8-a3b1-4c6e-9f2a-7b8c1d3e4f50', author: '', status: '', page: 1, dispute: '', mode: '' }).map((d) => d.id)).toEqual([1n, 3n]);
    expect(applyFilters(DEMO_DISPUTES, { request: '', author: DEMO_DISPUTES[1]!.challenger.slice(0, 10).toUpperCase(), status: '', page: 1, dispute: '', mode: '' }).map((d) => d.id)).toEqual([2n]);
    expect(applyFilters(DEMO_DISPUTES, { request: '', author: '', status: 'withdrawn', page: 1, dispute: '', mode: '' }).map((d) => d.id)).toEqual([2n]);
    expect(applyFilters(DEMO_DISPUTES, { request: '', author: '', status: 'open', page: 1, dispute: '', mode: '' })).toHaveLength(2);
  });
  it('paginates and clamps', () => {
    const items = Array.from({ length: 23 }, (_, i) => i);
    expect(paginate(items, 3, 10)).toMatchObject({ page: 3, pages: 3, items: [20, 21, 22] });
    expect(paginate(items, 99, 10).page).toBe(3);
    expect(paginate([], 1, 10)).toMatchObject({ page: 1, pages: 1, items: [] });
  });
  it('round-trips view state through the URL hash', () => {
    const v = { request: 'abc', author: '0x1', status: 'open' as const, page: 2, dispute: '7', mode: 'demo' as const };
    expect(parseHash(serializeHash(v))).toEqual(v);
    expect(parseHash('#/')).toEqual({ request: '', author: '', status: '', page: 1, dispute: '', mode: '' });
    expect(parseHash('#/?status=bogus&page=-3&mode=x').status).toBe('');
  });
});

describe('wallet chain switching', () => {
  const network = networkFile.network;
  const fake = (script: Record<string, (i: number) => unknown>): { provider: Eip1193Provider; calls: string[] } => {
    const calls: string[] = [];
    const counts: Record<string, number> = {};
    return {
      calls,
      provider: {
        request: async ({ method }) => {
          calls.push(method);
          counts[method] = (counts[method] ?? 0) + 1;
          const r = script[method]?.(counts[method]!);
          if (r instanceof Error) throw r;
          return r;
        },
      },
    };
  };
  it('parses hex and decimal chain ids', () => {
    expect(parseChainId('0xaa36a7')).toBe(11155111);
    expect(parseChainId(1)).toBe(1);
    expect(parseChainId(undefined)).toBeNull();
  });
  it('switches directly when the wallet knows the chain', async () => {
    const { provider, calls } = fake({ wallet_switchEthereumChain: () => null });
    expect(await switchOrAddChain(provider, network)).toEqual({ ok: true });
    expect(calls).toEqual(['wallet_switchEthereumChain']);
  });
  it('adds the chain on 4902 then switches again', async () => {
    const { provider, calls } = fake({
      wallet_switchEthereumChain: (i) => (i === 1 ? Object.assign(new Error('Unrecognized chain'), { code: 4902 }) : null),
      wallet_addEthereumChain: () => null,
    });
    expect(await switchOrAddChain(provider, network)).toEqual({ ok: true });
    expect(calls).toEqual(['wallet_switchEthereumChain', 'wallet_addEthereumChain', 'wallet_switchEthereumChain']);
  });
  it('reports user rejection without faking success', async () => {
    const { provider } = fake({ wallet_switchEthereumChain: () => Object.assign(new Error('User rejected the request'), { code: 4001 }) });
    expect(await switchOrAddChain(provider, network)).toMatchObject({ ok: false, rejected: true });
  });
});
