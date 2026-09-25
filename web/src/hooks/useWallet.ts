import { useCallback, useEffect, useMemo, useState } from 'react';
import type { Address } from 'viem';
import type { NetworkConfig } from '../lib/deployment';
import {
  getInjectedProvider,
  isUserRejection,
  parseChainId,
  readChainId,
  requestAccounts,
  silentAccounts,
  switchOrAddChain,
  type Eip1193Provider,
} from '../lib/wallet';

export interface WalletState {
  /** whether an EIP-1193 provider was found in the page */
  available: boolean;
  provider: Eip1193Provider | null;
  account: Address | null;
  chainId: number | null;
  connecting: boolean;
  switching: boolean;
  error: string | null;
  /** true when connected and on the registry chain */
  onRegistryChain: boolean;
  connect: () => Promise<void>;
  disconnect: () => void;
  switchChain: () => Promise<void>;
}

export function useWallet(network: NetworkConfig | null, providerOverride?: Eip1193Provider | null): WalletState {
  const provider = useMemo(() => (providerOverride === undefined ? getInjectedProvider() : providerOverride), [providerOverride]);
  const [account, setAccount] = useState<Address | null>(null);
  const [chainId, setChainId] = useState<number | null>(null);
  const [connecting, setConnecting] = useState(false);
  const [switching, setSwitching] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [userDisconnected, setUserDisconnected] = useState(false);

  useEffect(() => {
    if (!provider) return;
    let active = true;
    // Do not pop the wallet: only pick up an already-authorised account.
    silentAccounts(provider).then((accts) => {
      if (active && !userDisconnected) setAccount(accts[0] ?? null);
    });
    readChainId(provider)
      .then((id) => active && setChainId(id))
      .catch(() => active && setChainId(null));
    const onAccounts = (...args: unknown[]) => {
      const accts = (args[0] as string[]) ?? [];
      setAccount((accts[0] as Address | undefined) ?? null);
    };
    const onChain = (...args: unknown[]) => setChainId(parseChainId(args[0]));
    provider.on?.('accountsChanged', onAccounts);
    provider.on?.('chainChanged', onChain);
    return () => {
      active = false;
      provider.removeListener?.('accountsChanged', onAccounts);
      provider.removeListener?.('chainChanged', onChain);
    };
  }, [provider, userDisconnected]);

  const connect = useCallback(async () => {
    setError(null);
    if (!provider) {
      setError('No injected wallet (EIP-1193) was found in this browser. Install a browser wallet to write to the Sepolia registry; browsing works without one.');
      return;
    }
    setConnecting(true);
    try {
      const accts = await requestAccounts(provider);
      setUserDisconnected(false);
      setAccount(accts[0] ?? null);
      setChainId(await readChainId(provider));
      if (!accts[0]) setError('The wallet returned no account.');
    } catch (e) {
      setError(isUserRejection(e) ? 'You declined the connection request in your wallet.' : `Wallet connection failed: ${(e as Error).message ?? 'unknown error'}`);
    } finally {
      setConnecting(false);
    }
  }, [provider]);

  const disconnect = useCallback(() => {
    // Injected wallets do not expose a programmatic disconnect; forget the account in this page.
    setUserDisconnected(true);
    setAccount(null);
    setError(null);
  }, []);

  const switchChain = useCallback(async () => {
    if (!provider || !network) return;
    setError(null);
    setSwitching(true);
    try {
      const result = await switchOrAddChain(provider, network);
      if (!result.ok) setError(result.message);
      setChainId(await readChainId(provider));
    } finally {
      setSwitching(false);
    }
  }, [provider, network]);

  return {
    available: Boolean(provider),
    provider,
    account,
    chainId,
    connecting,
    switching,
    error,
    onRegistryChain: Boolean(account && network && chainId === network.chainId),
    connect,
    disconnect,
    switchChain,
  };
}
