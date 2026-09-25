// Demo mode data. Clearly labelled, never submitted anywhere, never mixed with live registry reads.
// Addresses and hashes below are synthetic placeholders and do not refer to real wallets or documents.
import { keccak256, stringToBytes, type Address, type Hex } from 'viem';
import type { Dispute, DisputeResponse } from './registry';
import { uuidToBytes16 } from './uuid';

const demoAddress = (label: string): Address =>
  (`0x${keccak256(stringToBytes(`imd-oracle-challenges-demo:${label}`)).slice(2, 42)}`) as Address;

const demoHash = (label: string): Hex => keccak256(stringToBytes(`demo-bytes:${label}`));

export const DEMO_CHALLENGER_A = demoAddress('challenger-a');
export const DEMO_CHALLENGER_B = demoAddress('challenger-b');
export const DEMO_RESPONDER = demoAddress('responder');

const T0 = 1_758_800_000n; // 2025-09-25T10:13:20Z, a fixed past timestamp so demo cards render stable dates

export const DEMO_DISPUTES: Dispute[] = [
  {
    id: 1n,
    challenger: DEMO_CHALLENGER_A,
    requestId: uuidToBytes16('0192d5f8-a3b1-4c6e-9f2a-7b8c1d3e4f50'),
    sourceChainId: 1n,
    attestationSnapshotHash: demoHash('attestation-1'),
    evidenceHash: demoHash('evidence-1'),
    evidenceURI: 'ipfs://bafybeigdyrzt5sfp7udm7hu76uh7y26nf3efuylqabf3oclgtqy55fbzdi/evidence.pdf',
    rationale: 'DEMO: the pinned block range ends before the event the question asks about, so the answer cannot have observed it.',
    createdAt: T0,
    withdrawnAt: 0n,
    status: 0,
  },
  {
    id: 2n,
    challenger: DEMO_CHALLENGER_B,
    requestId: uuidToBytes16('7c5d1f0e-2b3a-4d4c-8e9f-0a1b2c3d4e5f'),
    sourceChainId: 8453n,
    attestationSnapshotHash: demoHash('attestation-2'),
    evidenceHash: demoHash('evidence-2'),
    evidenceURI: 'https://example.org/evidence/base-pool-volume.csv',
    rationale: 'DEMO: the cited source reports a different figure for the same window. Challenger later withdrew this claim.',
    createdAt: T0 + 3_600n,
    withdrawnAt: T0 + 86_400n,
    status: 1,
  },
  {
    id: 3n,
    challenger: DEMO_CHALLENGER_A,
    requestId: uuidToBytes16('0192d5f8-a3b1-4c6e-9f2a-7b8c1d3e4f50'),
    sourceChainId: 1n,
    attestationSnapshotHash: demoHash('attestation-1'),
    evidenceHash: demoHash('evidence-3'),
    evidenceURI: 'javascript:alert(1)',
    rationale: 'DEMO: a second dispute on the same request with an invalid evidence URI, shown as text only and never linked.',
    createdAt: T0 + 7_200n,
    withdrawnAt: 0n,
    status: 0,
  },
];

export const DEMO_RESPONSES: Record<string, DisputeResponse[]> = {
  '1': [
    {
      author: DEMO_RESPONDER,
      evidenceHash: demoHash('response-1-0'),
      evidenceURI: 'https://example.org/notes/block-window-check.txt',
      text: 'DEMO: the window in the attestation matches the question; see the linked block-by-block notes.',
      createdAt: T0 + 1_800n,
    },
    {
      author: DEMO_CHALLENGER_A,
      evidenceHash: demoHash('response-1-1'),
      evidenceURI: 'ipfs://bafybeih2t4v6qfxlxlt4vt5hh5g6rjdz6ftbp6mchkuf2h6r2bscjdz4ee',
      text: 'DEMO: the notes look at toBlock+1, which is outside the pinned range.',
      createdAt: T0 + 5_400n,
    },
  ],
  '2': [],
  '3': [],
};

/** A synthetic attestation-shaped document so demo mode can exercise the hashing and download path. */
export const DEMO_ATTESTATION_JSON = JSON.stringify({
  requestId: '0192d5f8-a3b1-4c6e-9f2a-7b8c1d3e4f50',
  domain: { name: 'DEMO (not IMD)', version: '1', chainId: 1 },
  primaryType: 'OracleAttestation',
  message: {
    requestId: '0x0192d5f8a3b14c6e9f2a7b8c1d3e4f5000000000000000000000000000000000',
    chainId: 1,
    answer: '0x0000000000000000000000000000000000000000000000000000000000000001',
    figure: '42',
    fromBlock: 20_000_000,
    toBlock: 20_000_010,
    blockHash: '0x0000000000000000000000000000000000000000000000000000000000000000',
  },
  signer: '0x0000000000000000000000000000000000000000',
  signature: '0x',
  attestedAt: '2025-09-25T10:00:00.000Z',
  note: 'Synthetic demo document. Not produced by IMD.',
});

export const DEMO_REQUEST = {
  id: '0192d5f8-a3b1-4c6e-9f2a-7b8c1d3e4f50',
  status: 'demo',
  question: 'DEMO: How many transfers did contract X emit between the pinned blocks?',
  chainId: 1,
  answerType: 'uint256',
  window: { fromBlock: 20_000_000, toBlock: 20_000_010, toBlockHash: '0x0000000000000000000000000000000000000000000000000000000000000000' },
  signer: '0x0000000000000000000000000000000000000000',
  computedAnswer: '1',
  computedFigure: '42',
  attestedAt: '2025-09-25T10:00:00.000Z',
  createdAt: '2025-09-25T09:55:00.000Z',
  failure: null,
  raw: null,
};
