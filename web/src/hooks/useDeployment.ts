import { useEffect, useState } from 'react';
import { loadDeployment, type Deployment } from '../lib/deployment';

export type DeploymentState =
  | { status: 'loading' }
  | { status: 'ready'; deployment: Deployment }
  | { status: 'error'; message: string };

/** Loads ./imd-deployment.json + ABIs once. The app has no other source of addresses, chain id or ABIs. */
export function useDeployment(): DeploymentState {
  const [state, setState] = useState<DeploymentState>({ status: 'loading' });
  useEffect(() => {
    let cancelled = false;
    loadDeployment()
      .then((deployment) => {
        if (!cancelled) setState({ status: 'ready', deployment });
      })
      .catch((e: unknown) => {
        if (!cancelled) setState({ status: 'error', message: (e as Error).message ?? String(e) });
      });
    return () => {
      cancelled = true;
    };
  }, []);
  return state;
}
