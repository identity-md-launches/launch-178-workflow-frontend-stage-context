import { explorerAddressUrl, type Deployment } from '../lib/deployment';
import { formatTokenAmount } from '../lib/format';
import type { TokenInfo } from '../lib/registry';

export type TokenState = { status: 'loading' } | { status: 'ready'; info: TokenInfo } | { status: 'error'; message: string } | { status: 'demo' };

export function TokenPanel({ deployment, state }: { deployment: Deployment; state: TokenState }) {
  const { token, network } = deployment;
  return (
    <section className="block" aria-labelledby="token-heading">
      <h2 id="token-heading">
        OCTEST Token Information <span className="badge badge-warn">Separate {network.name} test token</span>
      </h2>
      <div className="card">
        <p className="small">
          <strong>Oracle Challenge Test (OCTEST)</strong> is the fixed-supply testnet launch token that IMD&rsquo;s project-launch
          policy requires for this experiment. It is <strong>not</strong> the IMD payment token, carries no value or return
          promise, and is <strong>not a prerequisite</strong> for anything on this page: the registry never reads, holds or
          moves OCTEST, and a zero OCTEST balance never blocks opening, answering or withdrawing a dispute. Registry actions
          never request token purchases or approvals.
        </p>
        <div className="token-grid" role="status" aria-live="polite">
          <dl className="kv">
            <dt>Name</dt>
            <dd>{state.status === 'ready' ? state.info.name : state.status === 'loading' ? 'Loading…' : deployment.manifest.contracts.length ? 'Oracle Challenge Test (per handoff)' : '—'}</dd>
            <dt>Symbol</dt>
            <dd>{state.status === 'ready' ? state.info.symbol : 'OCTEST (per handoff)'}</dd>
            <dt>Total supply</dt>
            <dd className="num">
              {state.status === 'ready'
                ? formatTokenAmount(state.info.totalSupply, state.info.decimals, state.info.symbol)
                : state.status === 'loading'
                  ? 'Loading…'
                  : state.status === 'demo'
                    ? 'Not read in demo mode'
                    : 'Unavailable'}
            </dd>
            <dt>Decimals</dt>
            <dd className="num">{state.status === 'ready' ? state.info.decimals : '18 (per handoff)'}</dd>
          </dl>
          <dl className="kv">
            <dt>{network.name} address</dt>
            <dd>
              <code translate="no" className="break">
                {token.address}
              </code>
            </dd>
            <dt>Explorer</dt>
            <dd>
              <a href={explorerAddressUrl(network, token.address)} target="_blank" rel="noopener noreferrer">
                View OCTEST on {network.name} explorer
              </a>
            </dd>
            <dt>ABI hash</dt>
            <dd>
              <code translate="no" className="break small">
                {token.abiHash}
              </code>{' '}
              <span className="badge badge-ok">matches handoff</span>
            </dd>
          </dl>
        </div>
        {state.status === 'error' && (
          <p className="small" role="alert" style={{ color: 'var(--danger-text)', marginTop: '0.5rem' }}>
            Live token reads failed: {state.message}. The address above still comes from the attested deployment configuration.
          </p>
        )}
      </div>
    </section>
  );
}
