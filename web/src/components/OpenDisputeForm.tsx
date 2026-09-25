import { useId, useState } from 'react';
import type { Hex } from 'viem';
import { MAX_TEXT_BYTES, imdAttestationUrl, imdRequestUrl, sourceChainLabel } from '../config';
import type { WalletState } from '../hooks/useWallet';
import { DEMO_ATTESTATION_JSON, DEMO_REQUEST } from '../lib/demo';
import type { NetworkConfig } from '../lib/deployment';
import { formatBytes, formatIso, formatInteger } from '../lib/format';
import {
  ImdApiError,
  describeAttestation,
  fetchAttestationSnapshot,
  fetchOracleRequest,
  snapshotFromBytes,
  type AttestationSnapshot,
  type OracleRequestSummary,
} from '../lib/imdApi';
import type { OpenDisputeArgs, TxPhase } from '../lib/registry';
import { checkEvidenceUri, checkText } from '../lib/uri';
import { isCompleteUuid, normalizeUuid, uuidToBytes16 } from '../lib/uuid';
import { EvidenceHashHelper, isValidHash32, type EvidenceHashValue } from './EvidenceHashHelper';
import { TxStatus } from './TxStatus';

type RequestState = { status: 'idle' } | { status: 'loading' } | { status: 'ready'; data: OracleRequestSummary } | { status: 'error'; message: string; kind?: string };
type AttestationState = { status: 'idle' } | { status: 'loading' } | { status: 'ready'; snapshot: AttestationSnapshot } | { status: 'error'; message: string; kind?: string };

export function OpenDisputeForm({
  network,
  demo,
  wallet,
  canWrite,
  busy,
  tx,
  onSubmit,
}: {
  network: NetworkConfig;
  demo: boolean;
  wallet: WalletState;
  canWrite: boolean;
  busy: boolean;
  tx: TxPhase;
  onSubmit: (args: OpenDisputeArgs) => void;
}) {
  const uuidId = useId();
  const chainId = useId();
  const uriId = useId();
  const rationaleId = useId();
  const attFileId = useId();

  const [uuid, setUuid] = useState('');
  const [request, setRequest] = useState<RequestState>({ status: 'idle' });
  const [attestation, setAttestation] = useState<AttestationState>({ status: 'idle' });
  const [sourceChain, setSourceChain] = useState('');
  const [evidence, setEvidence] = useState<EvidenceHashValue>({ hash: '', source: '' });
  const [uri, setUri] = useState('');
  const [rationale, setRationale] = useState('');
  const [touched, setTouched] = useState(false);

  const uuidOk = isCompleteUuid(uuid);
  const normalizedUuid = normalizeUuid(uuid);
  const sourceChainNum = /^\d+$/.test(sourceChain.trim()) ? BigInt(sourceChain.trim()) : null;
  const sourceChainOk = sourceChainNum !== null && sourceChainNum > 0n;
  const uriCheck = checkEvidenceUri(uri);
  const textCheck = checkText(rationale, MAX_TEXT_BYTES);
  const evidenceOk = isValidHash32(evidence.hash);
  const attestationOk = attestation.status === 'ready';
  const requestFetched = request.status === 'ready';
  const formValid = uuidOk && sourceChainOk && uriCheck.ok && textCheck.ok && evidenceOk && attestationOk;

  const blockReason = demo
    ? 'Demo mode: submission is disabled. Nothing entered here can be submitted as a live dispute.'
    : !wallet.account
      ? `Connect a wallet to open a dispute on ${network.name}.`
      : !wallet.onRegistryChain
        ? `Your wallet is on the wrong chain. Switch it to ${network.name} (chain ${network.chainId}).`
        : !canWrite
          ? 'Writes are unavailable.'
          : !attestationOk
            ? 'Fetch or choose the attestation so its exact bytes can be hashed.'
            : !formValid
              ? 'Complete every field above.'
              : null;

  const fetchFromImd = async () => {
    if (!normalizedUuid) return;
    setRequest({ status: 'loading' });
    setAttestation({ status: 'loading' });
    try {
      const data = await fetchOracleRequest(normalizedUuid);
      setRequest({ status: 'ready', data });
      if (data.chainId && !sourceChain) setSourceChain(String(data.chainId));
    } catch (e) {
      const err = e as ImdApiError;
      setRequest({ status: 'error', message: err.message, kind: err.kind });
    }
    try {
      const snapshot = await fetchAttestationSnapshot(normalizedUuid);
      setAttestation({ status: 'ready', snapshot });
    } catch (e) {
      const err = e as ImdApiError;
      setAttestation({ status: 'error', message: err.message, kind: err.kind });
    }
  };

  const loadDemo = () => {
    setUuid(DEMO_REQUEST.id);
    setRequest({ status: 'ready', data: DEMO_REQUEST });
    setAttestation({ status: 'ready', snapshot: snapshotFromBytes(new TextEncoder().encode(DEMO_ATTESTATION_JSON), 'demo') });
    setSourceChain(String(DEMO_REQUEST.chainId));
  };

  const onAttestationFile = async (file: File | undefined) => {
    if (!file) return;
    setAttestation({ status: 'loading' });
    try {
      const bytes = new Uint8Array(await file.arrayBuffer());
      setAttestation({ status: 'ready', snapshot: snapshotFromBytes(bytes, 'file', file.name) });
    } catch (e) {
      setAttestation({ status: 'error', message: `Could not read the file: ${(e as Error).message}` });
    }
  };

  const downloadAttestation = () => {
    if (attestation.status !== 'ready') return;
    const blob = new Blob([attestation.snapshot.bytes as BlobPart], { type: 'application/json' });
    const url = URL.createObjectURL(blob);
    const a = document.createElement('a');
    a.href = url;
    a.download = `attestation-${normalizedUuid ?? 'snapshot'}.json`;
    document.body.appendChild(a);
    a.click();
    a.remove();
    setTimeout(() => URL.revokeObjectURL(url), 1000);
  };

  const submit = () => {
    setTouched(true);
    if (!formValid || !canWrite || attestation.status !== 'ready' || !normalizedUuid || sourceChainNum === null) return;
    onSubmit({
      requestId: uuidToBytes16(normalizedUuid),
      sourceChainId: sourceChainNum,
      attestationSnapshotHash: attestation.snapshot.keccak,
      evidenceHash: evidence.hash as Hex,
      evidenceURI: uri.trim(),
      rationale,
    });
  };

  const att = attestation.status === 'ready' ? describeAttestation(attestation.snapshot.json) : null;

  return (
    <section className="block" aria-labelledby="open-heading">
      <h2 id="open-heading">
        Open a Dispute <span className="badge badge-warn">{network.name} registry transaction</span>
      </h2>
      <p className="small muted">
        Step 1 loads what the IMD API says about the request. Step 2 commits to evidence you host yourself. Step 3 previews the
        exact registry call. Nothing here verifies a signature or decides whether the answer is right.
      </p>
      <form
        className="card stack"
        noValidate
        onSubmit={(e) => {
          e.preventDefault();
          submit();
        }}
      >
        <fieldset>
          <legend>1. IMD oracle request</legend>
          <div className="field">
            <label htmlFor={uuidId}>Request UUID (complete, 36 characters)</label>
            <div className="row">
              <input
                id={uuidId}
                className="grow"
                type="text"
                name="request-uuid"
                autoComplete="off"
                spellCheck={false}
                placeholder="0192d5f8-a3b1-4c6e-9f2a-7b8c1d3e4f50…"
                value={uuid}
                onChange={(e) => setUuid(e.target.value)}
                aria-invalid={uuid !== '' && !uuidOk ? true : undefined}
                aria-describedby={`${uuidId}-hint`}
              />
              <button type="button" className="btn" onClick={() => void fetchFromImd()} disabled={!uuidOk || demo || request.status === 'loading'}>
                {request.status === 'loading' ? 'Fetching…' : 'Fetch From IMD API'}
              </button>
              {demo && (
                <button type="button" className="btn" onClick={loadDemo}>
                  Load Demo Request
                </button>
              )}
            </div>
            <p id={`${uuidId}-hint`} className={uuid !== '' && !uuidOk ? 'error' : 'hint'}>
              {uuid !== '' && !uuidOk ? 'Enter the full hyphenated UUID exactly as IMD shows it.' : demo ? 'Demo mode: the IMD API is not called.' : `Reads ${imdRequestUrl('{id}')} and /attestation.`}
            </p>
          </div>

          {request.status === 'error' && (
            <div className="notice notice-danger" role="alert">
              <p>
                Request lookup failed: {request.message}{' '}
                {request.kind === 'network' && normalizedUuid && (
                  <>
                    Try opening{' '}
                    <a href={imdRequestUrl(normalizedUuid)} target="_blank" rel="noopener noreferrer">
                      the request URL
                    </a>{' '}
                    directly.
                  </>
                )}
              </p>
            </div>
          )}
          {request.status === 'ready' && (
            <div className="notice" aria-live="polite">
              <p className="small muted" style={{ marginBottom: '0.3rem' }}>
                As advertised by the IMD API{request.data.status === 'demo' ? ' (DEMO, synthetic)' : ''}. Shown, not verified.
              </p>
              <dl className="kv small">
                <dt>Question</dt>
                <dd className="break">{request.data.question}</dd>
                <dt>Status</dt>
                <dd>{request.data.status}</dd>
                <dt>Answer</dt>
                <dd>
                  {request.data.computedAnswer !== null ? (
                    <>
                      <code translate="no">{request.data.computedAnswer}</code>
                      {request.data.computedFigure !== null && request.data.computedFigure !== request.data.computedAnswer && (
                        <>
                          {' '}
                          (figure <code translate="no">{request.data.computedFigure}</code>)
                        </>
                      )}
                      {request.data.answerType && <span className="muted"> · {request.data.answerType}</span>}
                    </>
                  ) : (
                    <span className="muted">none published{request.data.failure ? ` · ${request.data.failure}` : ''}</span>
                  )}
                </dd>
                <dt>Source chain</dt>
                <dd>{request.data.chainId !== null ? sourceChainLabel(request.data.chainId) : '—'}</dd>
                <dt>Pinned block range</dt>
                <dd className="num">
                  {request.data.window ? (
                    <>
                      {request.data.window.fromBlock !== null ? formatInteger(request.data.window.fromBlock) : '?'} →{' '}
                      {request.data.window.toBlock !== null ? formatInteger(request.data.window.toBlock) : '?'}
                      {request.data.window.toBlockHash && (
                        <>
                          {' '}
                          · toBlockHash{' '}
                          <code translate="no" className="break">
                            {request.data.window.toBlockHash}
                          </code>
                        </>
                      )}
                    </>
                  ) : (
                    '—'
                  )}
                </dd>
                <dt>API-advertised signer</dt>
                <dd>
                  {request.data.signer ? (
                    <code translate="no" className="break">
                      {request.data.signer}
                    </code>
                  ) : (
                    '—'
                  )}
                </dd>
                <dt>Attested at</dt>
                <dd>{formatIso(request.data.attestedAt)}</dd>
              </dl>
            </div>
          )}

          <div className="field" style={{ marginTop: '0.75rem' }}>
            <span className="label">Attestation snapshot (exact response bytes)</span>
            {attestation.status === 'loading' && (
              <p className="hint" role="status">
                <span className="spinner" aria-hidden="true" /> Fetching attestation…
              </p>
            )}
            {attestation.status === 'error' && (
              <div className="notice notice-warn" role="alert">
                <p>{attestation.message}</p>
                {attestation.kind === 'network' && normalizedUuid && (
                  <p className="small">
                    Workaround: open{' '}
                    <a href={imdAttestationUrl(normalizedUuid)} target="_blank" rel="noopener noreferrer">
                      the attestation URL
                    </a>{' '}
                    in a new tab, save the response exactly as received (no reformatting), then choose that file below. The
                    hash is computed over the file&rsquo;s raw bytes.
                  </p>
                )}
              </div>
            )}
            {attestation.status === 'ready' && att && (
              <div className="notice notice-ok" aria-live="polite" data-testid="attestation-ready">
                <p className="small" style={{ marginBottom: '0.3rem' }}>
                  Snapshot from {attestation.snapshot.origin === 'api' ? 'the IMD API response' : attestation.snapshot.origin === 'file' ? `file ${attestation.snapshot.fileName ?? ''}` : 'demo data (synthetic)'} ·{' '}
                  {formatBytes(attestation.snapshot.bytes.length)}. This is a hash of bytes, not a verified signature or a
                  proven-correct answer.
                </p>
                <dl className="kv small">
                  <dt>keccak256 of exact bytes</dt>
                  <dd>
                    <code translate="no" className="break" data-testid="attestation-hash">
                      {attestation.snapshot.keccak}
                    </code>
                  </dd>
                  <dt>API-advertised signer</dt>
                  <dd>{att.signer ? <code translate="no" className="break">{att.signer}</code> : '—'}</dd>
                  <dt>Attested answer</dt>
                  <dd>
                    {att.answer ? <code translate="no" className="break">{att.answer}</code> : '—'}
                    {att.figure ? <> (figure <code translate="no">{att.figure}</code>)</> : null}
                  </dd>
                  <dt>Pinned range</dt>
                  <dd className="num">
                    {att.fromBlock !== null && att.toBlock !== null ? `${formatInteger(att.fromBlock)} → ${formatInteger(att.toBlock)}` : '—'}
                    {att.chainId !== null && <> on {sourceChainLabel(att.chainId)}</>}
                  </dd>
                </dl>
                <button type="button" className="btn btn-sm" onClick={downloadAttestation}>
                  Download Exact Attestation Bytes
                </button>
              </div>
            )}
            <label htmlFor={attFileId} className="small" style={{ marginTop: '0.4rem' }}>
              Or choose a saved attestation file (hashed locally, never uploaded)
            </label>
            <input id={attFileId} type="file" name="attestation-file" accept="application/json,.json" onChange={(e) => void onAttestationFile(e.target.files?.[0])} />
          </div>

          <div className="field" style={{ marginTop: '0.75rem' }}>
            <label htmlFor={chainId}>Source chain id (the chain the request was about; not the registry chain)</label>
            <input
              id={chainId}
              type="text"
              inputMode="numeric"
              name="source-chain-id"
              autoComplete="off"
              spellCheck={false}
              placeholder="1…"
              value={sourceChain}
              onChange={(e) => setSourceChain(e.target.value)}
              aria-invalid={touched && !sourceChainOk ? true : undefined}
              aria-describedby={`${chainId}-hint`}
            />
            <p id={`${chainId}-hint`} className={touched && !sourceChainOk ? 'error' : 'hint'}>
              {sourceChainOk ? sourceChainLabel(sourceChainNum) : 'Positive integer chain id, prefilled from the IMD request when available.'}
              {requestFetched && request.data.chainId !== null && sourceChainNum !== null && BigInt(request.data.chainId) !== sourceChainNum && (
                <> · differs from the API-advertised chain {request.data.chainId}.</>
              )}
            </p>
          </div>
        </fieldset>

        <fieldset>
          <legend>2. Your evidence</legend>
          <EvidenceHashHelper label="Evidence hash" value={evidence} onChange={setEvidence} />
          <div className="field" style={{ marginTop: '0.75rem' }}>
            <label htmlFor={uriId}>Existing evidence URI (https:// or ipfs://) where those exact bytes are hosted</label>
            <input
              id={uriId}
              type="url"
              name="evidence-uri"
              autoComplete="off"
              spellCheck={false}
              placeholder="ipfs://bafy…/evidence.pdf…"
              value={uri}
              onChange={(e) => setUri(e.target.value)}
              aria-invalid={touched && !uriCheck.ok ? true : undefined}
              aria-describedby={`${uriId}-hint`}
            />
            <p id={`${uriId}-hint`} className={touched && !uriCheck.ok ? 'error' : 'hint'}>
              {uriCheck.ok ? `Will be linked as ${uriCheck.kind.toUpperCase()}.` : uriCheck.reason}
            </p>
          </div>
          <div className="field" style={{ marginTop: '0.75rem' }}>
            <label htmlFor={rationaleId}>Rationale (1–280 UTF-8 bytes)</label>
            <textarea
              id={rationaleId}
              name="rationale"
              autoComplete="off"
              value={rationale}
              onChange={(e) => setRationale(e.target.value)}
              maxLength={MAX_TEXT_BYTES}
              aria-invalid={touched && !textCheck.ok ? true : undefined}
              aria-describedby={`${rationaleId}-hint`}
            />
            <p id={`${rationaleId}-hint`} className={touched && !textCheck.ok ? 'error' : 'hint'}>
              <span className="num">{textCheck.bytes}</span>/{MAX_TEXT_BYTES} bytes{textCheck.reason ? ` · ${textCheck.reason}` : ''}
            </p>
          </div>
        </fieldset>

        <fieldset>
          <legend>3. Preview &amp; submit</legend>
          <dl className="kv small" data-testid="preview">
            <dt>Call</dt>
            <dd>
              <code translate="no">openDispute(requestId, sourceChainId, attestationSnapshotHash, evidenceHash, evidenceURI, rationale)</code> on{' '}
              {network.name} (chain {network.chainId})
            </dd>
            <dt>requestId (bytes16)</dt>
            <dd>
              <code translate="no" className="break">
                {normalizedUuid ? uuidToBytes16Safe(normalizedUuid) : '—'}
              </code>
            </dd>
            <dt>sourceChainId</dt>
            <dd className="num">{sourceChainOk ? sourceChainNum.toString() : '—'}</dd>
            <dt>attestationSnapshotHash</dt>
            <dd>
              <code translate="no" className="break">
                {attestation.status === 'ready' ? attestation.snapshot.keccak : '—'}
              </code>
            </dd>
            <dt>evidenceHash</dt>
            <dd>
              <code translate="no" className="break">
                {evidenceOk ? evidence.hash : '—'}
              </code>
            </dd>
            <dt>evidenceURI</dt>
            <dd className="break">{uri.trim() || '—'}</dd>
            <dt>rationale</dt>
            <dd className="break">{rationale || '—'}</dd>
            <dt>Challenger</dt>
            <dd>
              <code translate="no" className="break">
                {wallet.account ?? '— (connect a wallet)'}
              </code>
            </dd>
            <dt>Value / tokens</dt>
            <dd>None. No OCTEST, no approvals, no ETH transferred; only {network.name} gas.</dd>
          </dl>
          {blockReason && (
            <p className="small muted" data-testid="submit-block-reason">
              {blockReason}
            </p>
          )}
          <button type="submit" className="btn btn-primary" disabled={!canWrite || !formValid || busy} data-testid="submit-open">
            {busy ? 'Working…' : demo ? 'Open Dispute (disabled in demo mode)' : `Open Dispute on ${network.name}`}
          </button>
          <TxStatus tx={tx} network={network} />
        </fieldset>
      </form>
    </section>
  );
}

function uuidToBytes16Safe(uuid: string): string {
  try {
    return uuidToBytes16(uuid);
  } catch (e) {
    return (e as Error).message;
  }
}
