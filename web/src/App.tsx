import { useCallback, useEffect, useMemo, useState } from 'react';
import { About } from './components/About';
import { DataSourceBanner, type DataMode } from './components/DataSourceBanner';
import { DisputeList, type DisputesState } from './components/DisputeList';
import { OpenDisputeForm } from './components/OpenDisputeForm';
import { ResponsesPanel } from './components/ResponsesPanel';
import { TokenPanel, type TokenState } from './components/TokenPanel';
import { WalletBar } from './components/WalletBar';
import { useDeployment } from './hooks/useDeployment';
import { useHashState } from './hooks/useHashState';
import { useWallet } from './hooks/useWallet';
import { DEMO_DISPUTES, DEMO_RESPONSES } from './lib/demo';
import type { Deployment } from './lib/deployment';
import {
  RegistryReader,
  createReadClient,
  createWriteClient,
  readTokenInfo,
  sendRegistryWrite,
  type DisputeResponse,
  type OpenDisputeArgs,
  type RespondArgs,
  type TxPhase,
} from './lib/registry';
import { isUserRejection, type Eip1193Provider } from './lib/wallet';

export function App({ providerOverride }: { providerOverride?: Eip1193Provider | null }) {
  const deploymentState = useDeployment();
  return (
    <div className="page">
      <header className="site-header">
        <div className="title-block">
          <h1>IMD Oracle Challenges</h1>
          <p className="tagline">
            Record and browse evidence-backed challenges to IMD oracle answers. Public claims, not verdicts.
          </p>
          <ul className="badges" aria-label="Site status">
            <li>
              <span className="badge badge-warn">Unofficial community experiment</span>
            </li>
            <li>
              <span className="badge badge-warn">Sepolia testnet</span>
            </li>
            <li>
              <span className="badge badge-muted">Not an adjudicator · no verified verdicts</span>
            </li>
          </ul>
        </div>
      </header>
      <main id="main" tabIndex={-1}>
        {deploymentState.status === 'loading' && (
          <p role="status">
            <span className="spinner" aria-hidden="true" /> Loading deployment configuration…
          </p>
        )}
        {deploymentState.status === 'error' && (
          <div className="notice notice-danger" role="alert">
            <p>
              <strong>Deployment configuration could not be loaded.</strong> {deploymentState.message}
            </p>
            <p className="small">
              The app reads addresses, chain and ABIs only from <code>imd-deployment.json</code> next to this page and refuses to
              run against anything else.
            </p>
          </div>
        )}
        {deploymentState.status === 'ready' && <Loaded deployment={deploymentState.deployment} providerOverride={providerOverride} />}
      </main>
      <footer className="site-footer">
        <p>
          Unofficial community experiment on the Sepolia testnet. Not operated by IMD. Nothing on this site is a verified
          verdict; challenges are unproven claims by their submitting wallets. No mainnet transactions, no token purchases, no
          approvals, no private keys.
        </p>
      </footer>
    </div>
  );
}

function Loaded({ deployment, providerOverride }: { deployment: Deployment; providerOverride?: Eip1193Provider | null }) {
  const { network } = deployment;
  const [view, setView] = useHashState();
  const wallet = useWallet(network, providerOverride);
  const mode: DataMode = view.mode === 'demo' ? 'demo' : 'live';
  const demo = mode === 'demo';

  const reader = useMemo(() => new RegistryReader(createReadClient(network), deployment.registry.address, deployment.registry.abi), [deployment, network]);

  const [disputes, setDisputes] = useState<DisputesState>({ status: 'loading', loaded: 0, total: 0 });
  const [token, setToken] = useState<TokenState>({ status: 'loading' });
  const [reloadTick, setReloadTick] = useState(0);
  const [refreshKey, setRefreshKey] = useState(0);
  const [tx, setTx] = useState<TxPhase>({ phase: 'idle' });
  const [txTarget, setTxTarget] = useState<'open' | string>('open');
  const busy = tx.phase === 'simulating' || tx.phase === 'awaiting-signature' || tx.phase === 'pending';

  useEffect(() => {
    let cancelled = false;
    if (demo) {
      setDisputes({ status: 'ready', disputes: DEMO_DISPUTES, total: BigInt(DEMO_DISPUTES.length), truncated: false });
      setToken({ status: 'demo' });
      return;
    }
    setDisputes({ status: 'loading', loaded: 0, total: 0 });
    reader
      .getAllDisputes((loaded, total) => !cancelled && setDisputes({ status: 'loading', loaded, total }))
      .then((r) => !cancelled && setDisputes({ status: 'ready', ...r }))
      .catch((e: unknown) => !cancelled && setDisputes({ status: 'error', message: (e as Error).message ?? String(e) }));
    setToken({ status: 'loading' });
    readTokenInfo(reader.client, deployment.token.address, deployment.token.abi)
      .then((info) => !cancelled && setToken({ status: 'ready', info }))
      .catch((e: unknown) => !cancelled && setToken({ status: 'error', message: (e as Error).message ?? String(e) }));
    return () => {
      cancelled = true;
    };
  }, [demo, reader, deployment, reloadTick]);

  const loadResponses = useCallback(
    async (id: bigint): Promise<DisputeResponse[]> => (demo ? (DEMO_RESPONSES[id.toString()] ?? []) : reader.getAllResponses(id)),
    [demo, reader],
  );

  const canWrite = !demo && Boolean(wallet.account) && wallet.onRegistryChain && Boolean(wallet.provider) && deployment.registry.abiHashMatches;

  const runWrite = useCallback(
    async (target: string, fn: 'openDispute' | 'respond' | 'withdrawDispute', args: readonly unknown[]) => {
      if (!canWrite || !wallet.provider || !wallet.account) return;
      setTxTarget(target);
      setTx({ phase: 'idle' });
      const writer = createWriteClient(network, wallet.provider, wallet.account);
      await sendRegistryWrite(
        deployment,
        reader,
        writer,
        wallet.account,
        fn,
        args,
        (phase) => {
          setTx(phase);
          if (phase.phase === 'confirmed') {
            setReloadTick((t) => t + 1);
            setRefreshKey((k) => k + 1);
          }
        },
        isUserRejection,
      );
    },
    [canWrite, wallet.provider, wallet.account, network, deployment, reader],
  );

  const onOpen = (a: OpenDisputeArgs) =>
    void runWrite('open', 'openDispute', [a.requestId, a.sourceChainId, a.attestationSnapshotHash, a.evidenceHash, a.evidenceURI, a.rationale]);
  const onRespond = (a: RespondArgs) => void runWrite(a.disputeId.toString(), 'respond', [a.disputeId, a.evidenceHash, a.evidenceURI, a.text]);
  const onWithdraw = (id: bigint) => void runWrite(id.toString(), 'withdrawDispute', [id]);

  const liveError = !demo && disputes.status === 'error' ? disputes.message : null;
  const idle: TxPhase = { phase: 'idle' };

  return (
    <>
      <div className="stack">
        <WalletBar wallet={wallet} network={network} demoMode={demo} />
        <DataSourceBanner mode={mode} liveError={liveError} networkName={network.name} onMode={(m) => setView({ mode: m === 'live' ? '' : m, page: 1, dispute: '' })} />
      </div>

      <DisputeList
        state={disputes}
        view={view}
        onView={setView}
        network={network}
        demo={demo}
        onRetry={() => setReloadTick((t) => t + 1)}
        renderDetail={(d) => (
          <ResponsesPanel
            dispute={d}
            network={network}
            demo={demo}
            wallet={wallet}
            loadResponses={loadResponses}
            refreshKey={refreshKey}
            canWrite={canWrite}
            busy={busy}
            tx={txTarget === d.id.toString() ? tx : idle}
            onRespond={onRespond}
            onWithdraw={onWithdraw}
          />
        )}
      />

      <OpenDisputeForm network={network} demo={demo} wallet={wallet} canWrite={canWrite} busy={busy} tx={txTarget === 'open' ? tx : idle} onSubmit={onOpen} />

      <TokenPanel deployment={deployment} state={token} />
      <About deployment={deployment} />
    </>
  );
}
