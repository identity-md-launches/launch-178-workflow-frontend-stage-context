import { explorerTxUrl, type NetworkConfig } from '../lib/deployment';
import type { TxPhase } from '../lib/registry';

export function TxStatus({ tx, network }: { tx: TxPhase; network: NetworkConfig }) {
  if (tx.phase === 'idle') return null;
  const link = 'hash' in tx && tx.hash ? (
    <a href={explorerTxUrl(network, tx.hash)} target="_blank" rel="noopener noreferrer">
      View transaction on {network.name} explorer
    </a>
  ) : null;
  const cls =
    tx.phase === 'confirmed' ? 'notice notice-ok' : tx.phase === 'rejected' || tx.phase === 'failed' ? 'notice notice-danger' : 'notice';
  return (
    <div className={cls} role="status" aria-live="polite" data-testid="tx-status">
      {tx.phase === 'simulating' && (
        <p>
          <span className="spinner" aria-hidden="true" /> Simulating the call against the {network.name} registry…
        </p>
      )}
      {tx.phase === 'awaiting-signature' && (
        <p>
          <span className="spinner" aria-hidden="true" /> Waiting for you to confirm in your wallet… This is a {network.name}{' '}
          registry transaction. No value, tokens or approvals are involved.
        </p>
      )}
      {tx.phase === 'pending' && (
        <p>
          <span className="spinner" aria-hidden="true" /> Transaction sent to {network.name}; waiting for 1 confirmation… {link}
        </p>
      )}
      {tx.phase === 'confirmed' && (
        <p>
          Confirmed on {network.name} in block <span className="num">{tx.blockNumber.toString()}</span>. {link}
        </p>
      )}
      {tx.phase === 'rejected' && <p>{tx.message}</p>}
      {tx.phase === 'failed' && (
        <p>
          Transaction failed: {tx.message} {link}
        </p>
      )}
    </div>
  );
}
