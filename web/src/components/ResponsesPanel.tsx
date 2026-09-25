import { useEffect, useId, useState } from 'react';
import type { Hex } from 'viem';
import { MAX_TEXT_BYTES } from '../config';
import type { WalletState } from '../hooks/useWallet';
import { explorerAddressUrl, type NetworkConfig } from '../lib/deployment';
import { formatUnixSeconds, sameAddress, shortAddress } from '../lib/format';
import type { Dispute, DisputeResponse, RespondArgs, TxPhase } from '../lib/registry';
import { checkEvidenceUri, checkText } from '../lib/uri';
import { EvidenceHashHelper, isValidHash32, type EvidenceHashValue } from './EvidenceHashHelper';
import { EvidenceLink, SafeText } from './SafeText';
import { TxStatus } from './TxStatus';

export type ResponsesState =
  | { status: 'loading' }
  | { status: 'ready'; responses: DisputeResponse[] }
  | { status: 'error'; message: string };

export function ResponsesPanel({
  dispute,
  network,
  demo,
  wallet,
  loadResponses,
  refreshKey,
  canWrite,
  busy,
  tx,
  onRespond,
  onWithdraw,
}: {
  dispute: Dispute;
  network: NetworkConfig;
  demo: boolean;
  wallet: WalletState;
  loadResponses: (id: bigint) => Promise<DisputeResponse[]>;
  refreshKey: number;
  canWrite: boolean;
  busy: boolean;
  tx: TxPhase;
  onRespond: (args: RespondArgs) => void;
  onWithdraw: (id: bigint) => void;
}) {
  const [state, setState] = useState<ResponsesState>({ status: 'loading' });
  const [reloadTick, setReloadTick] = useState(0);
  useEffect(() => {
    let cancelled = false;
    setState({ status: 'loading' });
    loadResponses(dispute.id)
      .then((responses) => !cancelled && setState({ status: 'ready', responses }))
      .catch((e: unknown) => !cancelled && setState({ status: 'error', message: (e as Error).message ?? String(e) }));
    return () => {
      cancelled = true;
    };
  }, [dispute.id, loadResponses, refreshKey, reloadTick]);

  const isChallenger = sameAddress(wallet.account, dispute.challenger);
  const isOpen = dispute.status === 0;

  return (
    <div className="stack">
      <div>
        <h3 style={{ marginBottom: '0.25rem' }}>Responses</h3>
        {state.status === 'loading' && (
          <p className="small muted" role="status">
            <span className="spinner" aria-hidden="true" /> Loading responses…
          </p>
        )}
        {state.status === 'error' && (
          <p className="small" role="alert" style={{ color: 'var(--danger-text)' }}>
            Could not load responses: {state.message}{' '}
            <button type="button" className="btn-link" onClick={() => setReloadTick((t) => t + 1)}>
              Retry
            </button>
          </p>
        )}
        {state.status === 'ready' && state.responses.length === 0 && <p className="small muted">No responses yet.</p>}
        {state.status === 'ready' &&
          state.responses.map((r, i) => (
            <div className="response" key={i}>
              <div className="dispute-meta">
                <span>
                  #{i} by{' '}
                  {demo ? (
                    <code translate="no">{shortAddress(r.author)}</code>
                  ) : (
                    <a href={explorerAddressUrl(network, r.author)} target="_blank" rel="noopener noreferrer">
                      <code translate="no">{shortAddress(r.author)}</code>
                    </a>
                  )}
                  {sameAddress(r.author, dispute.challenger) && <span className="badge badge-muted"> challenger</span>}
                </span>
                <span>{formatUnixSeconds(r.createdAt)}</span>
              </div>
              <p className="dispute-text" style={{ margin: '0.3rem 0' }}>
                <SafeText text={r.text} />
              </p>
              <p className="small" style={{ margin: 0 }}>
                Evidence: <EvidenceLink uri={r.evidenceURI} />
                <br />
                keccak256{' '}
                <code translate="no" className="break">
                  {r.evidenceHash}
                </code>
              </p>
            </div>
          ))}
      </div>

      {isOpen ? (
        <RespondForm dispute={dispute} network={network} demo={demo} wallet={wallet} canWrite={canWrite} busy={busy} onRespond={onRespond} />
      ) : (
        <p className="small muted">This dispute is withdrawn. It keeps its record but accepts no more responses.</p>
      )}

      {isOpen && (
        <div>
          <h3 style={{ marginBottom: '0.25rem' }}>Withdraw</h3>
          <p className="small muted" style={{ marginBottom: '0.5rem' }}>
            Only the wallet that opened this dispute can withdraw it. Withdrawal is the challenger&rsquo;s own statement; every
            field and response stays on the public record.
          </p>
          {!isChallenger && wallet.account && <p className="small muted">Connected wallet is not this dispute&rsquo;s challenger.</p>}
          <button
            type="button"
            className="btn"
            disabled={!canWrite || !isChallenger || busy}
            onClick={() => {
              if (window.confirm(`Withdraw dispute #${dispute.id.toString()} on ${network.name}? This cannot be undone.`)) onWithdraw(dispute.id);
            }}
          >
            {demo ? 'Withdraw (disabled in demo mode)' : `Withdraw Dispute #${dispute.id.toString()} on ${network.name}`}
          </button>
        </div>
      )}
      <TxStatus tx={tx} network={network} />
    </div>
  );
}

function RespondForm({
  dispute,
  network,
  demo,
  wallet,
  canWrite,
  busy,
  onRespond,
}: {
  dispute: Dispute;
  network: NetworkConfig;
  demo: boolean;
  wallet: WalletState;
  canWrite: boolean;
  busy: boolean;
  onRespond: (args: RespondArgs) => void;
}) {
  const uriId = useId();
  const textId = useId();
  const [hash, setHash] = useState<EvidenceHashValue>({ hash: '', source: '' });
  const [uri, setUri] = useState('');
  const [text, setText] = useState('');
  const [touched, setTouched] = useState(false);

  const uriCheck = checkEvidenceUri(uri);
  const textCheck = checkText(text, MAX_TEXT_BYTES);
  const hashOk = isValidHash32(hash.hash);
  const valid = uriCheck.ok && textCheck.ok && hashOk;

  const reason = demo
    ? 'Demo mode: submissions are disabled.'
    : !wallet.account
      ? 'Connect a wallet to respond.'
      : !wallet.onRegistryChain
        ? `Switch your wallet to ${network.name} to respond.`
        : !canWrite
          ? 'Writes are unavailable.'
          : null;

  return (
    <form
      onSubmit={(e) => {
        e.preventDefault();
        setTouched(true);
        if (!valid || !canWrite) return;
        onRespond({ disputeId: dispute.id, evidenceHash: hash.hash as Hex, evidenceURI: uri.trim(), text });
      }}
      noValidate
      className="stack"
      aria-labelledby={`respond-${dispute.id.toString()}-heading`}
    >
      <h3 id={`respond-${dispute.id.toString()}-heading`} style={{ margin: 0 }}>
        Append a Response
      </h3>
      <p className="small muted" style={{ margin: 0 }}>
        Anyone may respond while the dispute is open. Responses are public, permanent and attributed to your wallet.
      </p>
      <EvidenceHashHelper label="Response evidence hash" value={hash} onChange={setHash} />
      <div className="field">
        <label htmlFor={uriId}>Evidence URI (https:// or ipfs://)</label>
        <input
          id={uriId}
          type="url"
          name="response-evidence-uri"
          autoComplete="off"
          spellCheck={false}
          placeholder="https://example.org/evidence.pdf…"
          value={uri}
          onChange={(e) => setUri(e.target.value)}
          aria-invalid={touched && !uriCheck.ok ? true : undefined}
          aria-describedby={`${uriId}-hint`}
        />
        <p id={`${uriId}-hint`} className={touched && !uriCheck.ok ? 'error' : 'hint'}>
          {!uriCheck.ok ? uriCheck.reason : `Will be linked as ${uriCheck.kind.toUpperCase()}.`}
        </p>
      </div>
      <div className="field">
        <label htmlFor={textId}>Response text</label>
        <textarea
          id={textId}
          name="response-text"
          autoComplete="off"
          value={text}
          onChange={(e) => setText(e.target.value)}
          maxLength={MAX_TEXT_BYTES}
          aria-invalid={touched && !textCheck.ok ? true : undefined}
          aria-describedby={`${textId}-hint`}
        />
        <p id={`${textId}-hint`} className={touched && !textCheck.ok ? 'error' : 'hint'}>
          <span className="num">{textCheck.bytes}</span>/{MAX_TEXT_BYTES} bytes{textCheck.reason ? ` · ${textCheck.reason}` : ''}
        </p>
      </div>
      {reason && <p className="small muted">{reason}</p>}
      <div>
        <button type="submit" className="btn btn-primary" disabled={!canWrite || busy || !valid}>
          {busy ? 'Working…' : `Append Response on ${network.name}`}
        </button>
      </div>
    </form>
  );
}
