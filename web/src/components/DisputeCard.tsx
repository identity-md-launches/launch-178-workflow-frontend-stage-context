import type { ReactNode } from 'react';
import { sourceChainLabel } from '../config';
import { explorerAddressUrl, type NetworkConfig } from '../lib/deployment';
import { formatUnixSeconds, shortAddress } from '../lib/format';
import { STATUS_LABEL, type Dispute } from '../lib/registry';
import { bytes16ToUuid } from '../lib/uuid';
import { EvidenceLink, SafeText } from './SafeText';

export function DisputeCard({
  dispute,
  network,
  demo,
  expanded,
  onToggle,
  children,
}: {
  dispute: Dispute;
  network: NetworkConfig;
  demo: boolean;
  expanded: boolean;
  onToggle: () => void;
  children?: ReactNode;
}) {
  const status = STATUS_LABEL[dispute.status];
  const uuid = bytes16ToUuid(dispute.requestId);
  const panelId = `dispute-${dispute.id.toString()}-detail`;
  return (
    <article className={`card${demo ? ' card-demo' : ''}`} aria-labelledby={`dispute-${dispute.id.toString()}-title`}>
      <div className="dispute-head">
        <div className="dispute-title" id={`dispute-${dispute.id.toString()}-title`}>
          Dispute #{dispute.id.toString()} <span className="badge badge-warn">Unproven community claim</span>
          {demo && <span className="badge badge-demo">Demo data</span>}
        </div>
        <span className={`status-pill ${status === 'Open' ? 'status-open' : 'status-withdrawn'}`}>{status}</span>
      </div>
      <div className="dispute-meta">
        <span>
          Request{' '}
          <code translate="no" className="break">
            {uuid}
          </code>
        </span>
        <span>Source chain: {sourceChainLabel(dispute.sourceChainId)}</span>
        <span>
          Challenger{' '}
          {demo ? (
            <code translate="no">{shortAddress(dispute.challenger)}</code>
          ) : (
            <a href={explorerAddressUrl(network, dispute.challenger)} target="_blank" rel="noopener noreferrer">
              <code translate="no">{shortAddress(dispute.challenger)}</code>
            </a>
          )}
        </span>
        <span>Opened {formatUnixSeconds(dispute.createdAt)}</span>
        {dispute.status === 1 && <span>Withdrawn {formatUnixSeconds(dispute.withdrawnAt)}</span>}
      </div>
      <p className="dispute-text">
        <SafeText text={dispute.rationale} />
      </p>
      <dl className="kv small">
        <dt>Evidence URI</dt>
        <dd>
          <EvidenceLink uri={dispute.evidenceURI} />
        </dd>
        <dt>Evidence keccak256</dt>
        <dd>
          <code translate="no" className="break">
            {dispute.evidenceHash}
          </code>
        </dd>
        <dt>Attestation snapshot keccak256</dt>
        <dd>
          <code translate="no" className="break">
            {dispute.attestationSnapshotHash}
          </code>
        </dd>
      </dl>
      <p className="small muted" style={{ margin: '0.25rem 0 0.5rem' }}>
        Registry record on {network.name} (chain {network.chainId}); the source chain above is the challenger&rsquo;s claim about
        the oracle request, not where this record lives. Hashes are the challenger&rsquo;s commitments, not verified facts.
      </p>
      <button type="button" className="btn btn-sm" aria-expanded={expanded} aria-controls={panelId} onClick={onToggle}>
        {expanded ? 'Hide Responses' : 'Show Responses & Actions'}
      </button>
      {expanded && (
        <div id={panelId} className="responses">
          {children}
        </div>
      )}
    </article>
  );
}
