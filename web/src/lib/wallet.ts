import type { Address } from 'viem';
import { walletAddChainParams, type NetworkConfig } from './deployment';

/** Minimal EIP-1193 provider surface used by this app. */
export interface Eip1193Provider {
  request(args: { method: string; params?: unknown[] | object }): Promise<unknown>;
  on?(event: string, listener: (...args: unknown[]) => void): void;
  removeListener?(event: string, listener: (...args: unknown[]) => void): void;
  isMetaMask?: boolean;
}

declare global {
  interface Window {
    ethereum?: Eip1193Provider;
  }
}

export function getInjectedProvider(): Eip1193Provider | null {
  if (typeof window === 'undefined') return null;
  const p = window.ethereum;
  return p && typeof p.request === 'function' ? p : null;
}

export interface ProviderRpcError {
  code?: number;
  message?: string;
  data?: unknown;
}

export const isUserRejection = (e: unknown): boolean => {
  const err = e as ProviderRpcError & { cause?: ProviderRpcError; name?: string };
  return (
    err?.code === 4001 ||
    err?.cause?.code === 4001 ||
    err?.name === 'UserRejectedRequestError' ||
    /user rejected|user denied|rejected the request/i.test(String(err?.message ?? ''))
  );
};

const isUnknownChain = (e: unknown): boolean => {
  const err = e as ProviderRpcError & { data?: { originalError?: ProviderRpcError } };
  return (
    err?.code === 4902 ||
    err?.data?.originalError?.code === 4902 ||
    /unrecognized chain|unknown chain|not added|wallet_addEthereumChain/i.test(String(err?.message ?? ''))
  );
};

export function parseChainId(value: unknown): number | null {
  if (typeof value === 'number') return value;
  if (typeof value === 'string') {
    const n = value.startsWith('0x') ? parseInt(value, 16) : parseInt(value, 10);
    return Number.isFinite(n) ? n : null;
  }
  return null;
}

export async function readChainId(provider: Eip1193Provider): Promise<number | null> {
  return parseChainId(await provider.request({ method: 'eth_chainId' }));
}

export async function requestAccounts(provider: Eip1193Provider): Promise<Address[]> {
  const accounts = (await provider.request({ method: 'eth_requestAccounts' })) as string[];
  return (accounts ?? []).map((a) => a as Address);
}

export async function silentAccounts(provider: Eip1193Provider): Promise<Address[]> {
  try {
    const accounts = (await provider.request({ method: 'eth_accounts' })) as string[];
    return (accounts ?? []).map((a) => a as Address);
  } catch {
    return [];
  }
}

export type SwitchResult = { ok: true } | { ok: false; rejected: boolean; message: string };

/**
 * wallet_switchEthereumChain; on 4902 / unknown chain fall back to wallet_addEthereumChain with parameters
 * derived from the deployment manifest's network block, then switch again.
 */
export async function switchOrAddChain(provider: Eip1193Provider, network: NetworkConfig): Promise<SwitchResult> {
  const hexId = `0x${network.chainId.toString(16)}`;
  try {
    await provider.request({ method: 'wallet_switchEthereumChain', params: [{ chainId: hexId }] });
    return { ok: true };
  } catch (e) {
    if (isUserRejection(e)) return { ok: false, rejected: true, message: 'You declined the network switch in your wallet.' };
    if (!isUnknownChain(e)) {
      return { ok: false, rejected: false, message: `Wallet refused to switch: ${(e as Error).message ?? 'unknown error'}` };
    }
  }
  try {
    await provider.request({ method: 'wallet_addEthereumChain', params: [walletAddChainParams(network)] });
  } catch (e) {
    if (isUserRejection(e)) return { ok: false, rejected: true, message: `You declined adding ${network.name} to your wallet.` };
    return { ok: false, rejected: false, message: `Wallet could not add ${network.name}: ${(e as Error).message ?? 'unknown error'}` };
  }
  try {
    await provider.request({ method: 'wallet_switchEthereumChain', params: [{ chainId: hexId }] });
    return { ok: true };
  } catch (e) {
    if (isUserRejection(e)) return { ok: false, rejected: true, message: 'You declined the network switch in your wallet.' };
    return { ok: false, rejected: false, message: `Added ${network.name} but the wallet did not switch to it.` };
  }
}
