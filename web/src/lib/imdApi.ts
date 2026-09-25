import { keccak256, type Hex } from 'viem';
import { imdAttestationUrl, imdRequestUrl } from '../config';

/** The subset of the IMD oracle request record this app displays. Everything is shown as "API-advertised". */
export interface OracleRequestSummary {
  id: string;
  status: string;
  question: string;
  chainId: number | null;
  answerType: string | null;
  window: { fromBlock: number | null; toBlock: number | null; toBlockHash: string | null } | null;
  signer: string | null;
  computedAnswer: string | null;
  computedFigure: string | null;
  attestedAt: string | null;
  createdAt: string | null;
  failure: string | null;
  raw: unknown;
}

export interface AttestationSnapshot {
  /** exact response bytes as received */
  bytes: Uint8Array;
  /** keccak256 of those exact bytes */
  keccak: Hex;
  /** parsed JSON, or null if the body was not JSON */
  json: unknown;
  /** where the bytes came from */
  origin: 'api' | 'file' | 'demo';
  fileName?: string;
}

export type ApiFailureKind = 'network' | 'not_found' | 'not_attested' | 'http' | 'invalid';

export class ImdApiError extends Error {
  kind: ApiFailureKind;
  status?: number;
  constructor(kind: ApiFailureKind, message: string, status?: number) {
    super(message);
    this.kind = kind;
    this.status = status;
  }
}

type Fetcher = (input: string) => Promise<Response>;
const defaultFetch: Fetcher = (u) => fetch(u, { headers: { accept: 'application/json' } });

function str(v: unknown): string | null {
  return typeof v === 'string' ? v : v === null || v === undefined ? null : String(v);
}
function num(v: unknown): number | null {
  return typeof v === 'number' && Number.isFinite(v) ? v : null;
}

export function summarizeRequest(raw: unknown): OracleRequestSummary {
  if (!raw || typeof raw !== 'object') throw new ImdApiError('invalid', 'IMD API returned a non-object body');
  const r = raw as Record<string, unknown>;
  if (typeof r.id !== 'string' || typeof r.question !== 'string') {
    throw new ImdApiError('invalid', 'IMD API response is missing id or question');
  }
  const w = r.window as Record<string, unknown> | undefined;
  const computed = r.computed as Record<string, unknown> | null | undefined;
  return {
    id: r.id,
    status: str(r.status) ?? 'unknown',
    question: r.question,
    chainId: num(r.chainId),
    answerType: str(r.answerType),
    window: w
      ? { fromBlock: num(w.fromBlock), toBlock: num(w.toBlock), toBlockHash: str(w.toBlockHash) }
      : null,
    signer: str(r.signer),
    computedAnswer: computed ? str(computed.answer) : null,
    computedFigure: computed ? str(computed.figure) : null,
    attestedAt: str(r.attestedAt),
    createdAt: str(r.createdAt),
    failure: str(r.failure),
    raw,
  };
}

async function classifyFailure(res: Response): Promise<ImdApiError> {
  let body: unknown = null;
  try {
    body = await res.json();
  } catch {
    /* not JSON */
  }
  const code = body && typeof body === 'object' ? String((body as Record<string, unknown>).error ?? '') : '';
  const detail = body && typeof body === 'object' ? str((body as Record<string, unknown>).detail) : null;
  if (res.status === 404 && code === 'unknown_request') {
    return new ImdApiError('not_found', 'IMD does not know this request id.', 404);
  }
  if (res.status === 404 && code === 'not_attested') {
    return new ImdApiError('not_attested', detail ? `No attestation: ${detail}.` : 'This request has no attestation.', 404);
  }
  return new ImdApiError('http', `IMD API answered HTTP ${res.status}${code ? ` (${code})` : ''}.`, res.status);
}

export async function fetchOracleRequest(id: string, fetcher: Fetcher = defaultFetch): Promise<OracleRequestSummary> {
  let res: Response;
  try {
    res = await fetcher(imdRequestUrl(id));
  } catch (e) {
    throw new ImdApiError('network', `Could not reach the IMD API (${(e as Error).message}).`);
  }
  if (!res.ok) throw await classifyFailure(res);
  let json: unknown;
  try {
    json = await res.json();
  } catch {
    throw new ImdApiError('invalid', 'IMD API returned a body that is not JSON.');
  }
  return summarizeRequest(json);
}

/** Wraps raw bytes as an attestation snapshot, hashing exactly those bytes. */
export function snapshotFromBytes(bytes: Uint8Array, origin: AttestationSnapshot['origin'], fileName?: string): AttestationSnapshot {
  let json: unknown = null;
  try {
    json = JSON.parse(new TextDecoder().decode(bytes));
  } catch {
    json = null;
  }
  return { bytes, keccak: keccak256(bytes), json, origin, fileName };
}

/**
 * Fetches /attestation and hashes the exact response bytes. The public IMD attestation endpoint currently
 * omits CORS headers, so a browser fetch may fail with a network error even though the URL works in a new tab;
 * callers should then offer the manual-file path (snapshotFromBytes with origin 'file').
 */
export async function fetchAttestationSnapshot(id: string, fetcher: Fetcher = defaultFetch): Promise<AttestationSnapshot> {
  let res: Response;
  try {
    res = await fetcher(imdAttestationUrl(id));
  } catch (e) {
    throw new ImdApiError(
      'network',
      `The browser could not fetch the attestation (${(e as Error).message}). This is usually a missing CORS header on the IMD API, not a missing attestation.`,
    );
  }
  if (!res.ok) throw await classifyFailure(res);
  const bytes = new Uint8Array(await res.arrayBuffer());
  return snapshotFromBytes(bytes, 'api');
}

/** Pulls display fields out of an attestation JSON body without trusting its shape. */
export function describeAttestation(json: unknown): {
  signer: string | null;
  attestedAt: string | null;
  answer: string | null;
  figure: string | null;
  chainId: number | null;
  fromBlock: number | null;
  toBlock: number | null;
  blockHash: string | null;
  requestIdBytes32: string | null;
  signature: string | null;
} {
  const a = (json && typeof json === 'object' ? json : {}) as Record<string, unknown>;
  const m = (a.message && typeof a.message === 'object' ? a.message : {}) as Record<string, unknown>;
  return {
    signer: str(a.signer),
    attestedAt: str(a.attestedAt),
    answer: str(m.answer),
    figure: str(m.figure),
    chainId: num(m.chainId),
    fromBlock: num(m.fromBlock),
    toBlock: num(m.toBlock),
    blockHash: str(m.blockHash),
    requestIdBytes32: str(m.requestId),
    signature: str(a.signature),
  };
}
