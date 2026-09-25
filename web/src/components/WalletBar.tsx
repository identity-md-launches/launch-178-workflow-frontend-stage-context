import type { WalletState } from '../hooks/useWallet';
import type { NetworkConfig } from '../lib/deployment';
import { shortAddress } from '../lib/format';

export function WalletBar({ wallet, network, demoMode }: { wallet: WalletState; network: NetworkConfig; demoMode: boolean }) {
  const wrongChain = Boolean(wallet.account && wallet.chainId !== network.chainId);
  return (
    <div className="card" aria-labelledby="wallet-heading">
      <div className="row">
        <h2 id="wallet-heading" style={{ margin: 0, fontSize: '1.05rem' }}>
          Wallet
        </h2>
        <span className="badge badge-warn">{network.name} testnet writes only</span>
        {demoMode && <span className="badge badge-demo">Demo mode: submissions disabled</span>}
      </div>
      <p className="small muted" style={{ margin: '0.4rem 0 0.6rem' }}>
        Browsing needs no wallet. Connect an injected wallet only to open, answer or withdraw disputes on the {network.name}{' '}
        registry. Never mainnet, never token approvals, never a private key.
      </p>
      <div className="row" role="status" aria-live="polite">
        {!wallet.account ? (
          <>
            <span className="badge badge-muted">Not connected</span>
            <button type="button" className="btn btn-primary" onClick={() => void wallet.connect()} disabled={wallet.connecting || demoMode}>
              {wallet.connecting ? 'Connecting…' : 'Connect Wallet'}
            </button>
            {!wallet.available && <span className="small muted">No injected (EIP-1193) wallet detected in this browser.</span>}
          </>
        ) : (
          <>
            <span className="badge badge-ok">
              Connected <code translate="no">{shortAddress(wallet.account)}</code>
            </span>
            <span className={`badge ${wrongChain ? 'badge-warn' : 'badge-ok'}`}>
              {wallet.chainId === null ? 'Chain unknown' : wallet.chainId === network.chainId ? `${network.name} (chain ${network.chainId})` : `Wrong chain: ${wallet.chainId}`}
            </span>
            {wrongChain && (
              <button type="button" className="btn btn-primary" onClick={() => void wallet.switchChain()} disabled={wallet.switching}>
                {wallet.switching ? 'Switching…' : `Switch to ${network.name}`}
              </button>
            )}
            <button type="button" className="btn btn-sm" onClick={wallet.disconnect}>
              Forget Connection
            </button>
          </>
        )}
      </div>
      {wallet.error && (
        <p className="error small" role="alert" style={{ marginTop: '0.5rem', color: 'var(--danger-text)' }}>
          {wallet.error}
        </p>
      )}
    </div>
  );
}
