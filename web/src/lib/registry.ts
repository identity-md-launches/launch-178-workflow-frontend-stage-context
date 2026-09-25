import {
  createPublicClient,
  createWalletClient,
  custom,
  defineChain,
  fallback,
  http,
  type Abi,
  type Address,
  type Hex,
  type PublicClient,
  type WalletClient,
} from 'viem';
import { MAX_DISPUTES_LOADED, MAX_PAGE_LIMIT } from '../config';
import type { Deployment, NetworkConfig } from './deployment';
import type { Eip1193Provider } from './wallet';

export type DisputeStatus = 0 | 1;
export const STATUS_LABEL: Record<DisputeStatus, 'Open' | 'Withdrawn'> = { 0: 'Open', 1: 'Withdrawn' };

export interface Dispute {
  id: bigint;
  challenger: Address;
  requestId: Hex; // bytes16
  sourceChainId: bigint;
  attestationSnapshotHash: Hex;
  evidenceHash: Hex;
  evidenceURI: string;
  rationale: string;
  createdAt: bigint;
  withdrawnAt: bigint;
  status: DisputeStatus;
}

export interface DisputeResponse {
  author: Address;
  evidenceHash: Hex;
  evidenceURI: string;
  text: string;
  createdAt: bigint;
}

export interface TokenInfo {
  name: string;
  symbol: string;
  decimals: number;
  totalSupply: bigint;
}

export function toViemChain(network: NetworkConfig) {
  return defineChain({
    id: network.chainId,
    name: network.name,
    testnet: network.testnet,
    nativeCurrency: network.nativeCurrency,
    rpcUrls: { default: { http: network.rpcUrls } },
    blockExplorers: { default: { name: 'Explorer', url: network.explorer } },
  });
}

/** Public read client over the manifest's public RPC URLs (tries them in order). */
export function createReadClient(network: NetworkConfig): PublicClient {
  const chain = toViemChain(network);
  return createPublicClient({
    chain,
    transport: fallback(
      network.rpcUrls.map((url) => http(url, { timeout: 15_000, retryCount: 1 })),
      { rank: false },
    ),
    batch: { multicall: false },
  }) as PublicClient;
}

export function createWriteClient(network: NetworkConfig, provider: Eip1193Provider, account: Address): WalletClient {
  return createWalletClient({ chain: toViemChain(network), transport: custom(provider), account });
}

type RawDispute = {
  id: bigint;
  challenger: Address;
  requestId: Hex;
  sourceChainId: bigint;
  attestationSnapshotHash: Hex;
  evidenceHash: Hex;
  evidenceURI: string;
  rationale: string;
  createdAt: bigint;
  withdrawnAt: bigint;
  status: number;
};

const normDispute = (d: RawDispute): Dispute => ({ ...d, status: (d.status === 1 ? 1 : 0) as DisputeStatus });

export class RegistryReader {
  readonly client: PublicClient;
  readonly address: Address;
  readonly abi: Abi;
  constructor(client: PublicClient, address: Address, abi: Abi) {
    this.client = client;
    this.address = address;
    this.abi = abi;
  }

  async disputeCount(): Promise<bigint> {
    return (await this.client.readContract({ address: this.address, abi: this.abi, functionName: 'disputeCount' })) as bigint;
  }

  async getDisputes(offset: bigint, limit: number): Promise<Dispute[]> {
    const page = (await this.client.readContract({
      address: this.address,
      abi: this.abi,
      functionName: 'getDisputes',
      args: [offset, BigInt(limit)],
    })) as RawDispute[];
    return page.map(normDispute);
  }

  async getDispute(id: bigint): Promise<Dispute> {
    const d = (await this.client.readContract({
      address: this.address,
      abi: this.abi,
      functionName: 'getDispute',
      args: [id],
    })) as RawDispute;
    return normDispute(d);
  }

  /** Pages through every dispute (contract pages of MAX_PAGE_LIMIT), bounded by MAX_DISPUTES_LOADED. */
  async getAllDisputes(onProgress?: (loaded: number, total: number) => void): Promise<{ disputes: Dispute[]; total: bigint; truncated: boolean }> {
    const total = await this.disputeCount();
    const cap = BigInt(MAX_DISPUTES_LOADED);
    const target = total < cap ? total : cap;
    const disputes: Dispute[] = [];
    let offset = 0n;
    while (offset < target) {
      const remaining = Number(target - offset);
      const limit = Math.min(MAX_PAGE_LIMIT, remaining);
      const page = await this.getDisputes(offset, limit);
      if (page.length === 0) break;
      disputes.push(...page);
      offset += BigInt(page.length);
      onProgress?.(disputes.length, Number(total));
    }
    return { disputes, total, truncated: total > target };
  }

  async responseCount(id: bigint): Promise<bigint> {
    return (await this.client.readContract({
      address: this.address,
      abi: this.abi,
      functionName: 'responseCount',
      args: [id],
    })) as bigint;
  }

  async getResponses(id: bigint, offset: bigint, limit: number): Promise<DisputeResponse[]> {
    return (await this.client.readContract({
      address: this.address,
      abi: this.abi,
      functionName: 'getResponses',
      args: [id, offset, BigInt(limit)],
    })) as DisputeResponse[];
  }

  async getAllResponses(id: bigint): Promise<DisputeResponse[]> {
    const total = await this.responseCount(id);
    const out: DisputeResponse[] = [];
    let offset = 0n;
    while (offset < total) {
      const limit = Math.min(MAX_PAGE_LIMIT, Number(total - offset));
      const page = await this.getResponses(id, offset, limit);
      if (page.length === 0) break;
      out.push(...page);
      offset += BigInt(page.length);
    }
    return out;
  }
}

export async function readTokenInfo(client: PublicClient, address: Address, abi: Abi): Promise<TokenInfo> {
  const [name, symbol, decimals, totalSupply] = await Promise.all([
    client.readContract({ address, abi, functionName: 'name' }) as Promise<string>,
    client.readContract({ address, abi, functionName: 'symbol' }) as Promise<string>,
    client.readContract({ address, abi, functionName: 'decimals' }) as Promise<number>,
    client.readContract({ address, abi, functionName: 'totalSupply' }) as Promise<bigint>,
  ]);
  return { name, symbol, decimals: Number(decimals), totalSupply };
}

export interface OpenDisputeArgs {
  requestId: Hex;
  sourceChainId: bigint;
  attestationSnapshotHash: Hex;
  evidenceHash: Hex;
  evidenceURI: string;
  rationale: string;
}

export interface RespondArgs {
  disputeId: bigint;
  evidenceHash: Hex;
  evidenceURI: string;
  text: string;
}

export type TxPhase =
  | { phase: 'idle' }
  | { phase: 'simulating' }
  | { phase: 'awaiting-signature' }
  | { phase: 'pending'; hash: Hex }
  | { phase: 'confirmed'; hash: Hex; blockNumber: bigint }
  | { phase: 'rejected'; message: string }
  | { phase: 'failed'; message: string; hash?: Hex };

/**
 * Simulates then sends a registry write. The wallet signs; this app never holds keys. Registry writes never
 * involve OCTEST, approvals or value.
 */
export async function sendRegistryWrite(
  deployment: Deployment,
  reader: RegistryReader,
  wallet: WalletClient,
  account: Address,
  functionName: 'openDispute' | 'respond' | 'withdrawDispute',
  args: readonly unknown[],
  onPhase: (p: TxPhase) => void,
  isRejection: (e: unknown) => boolean,
): Promise<void> {
  const { address, abi } = deployment.registry;
  const chain = toViemChain(deployment.network);
  onPhase({ phase: 'simulating' });
  let request;
  try {
    ({ request } = await reader.client.simulateContract({ address, abi, functionName, args, account, chain }));
  } catch (e) {
    onPhase({ phase: 'failed', message: describeContractError(e) });
    return;
  }
  onPhase({ phase: 'awaiting-signature' });
  let hash: Hex;
  try {
    hash = await wallet.writeContract({ ...request, account, chain });
  } catch (e) {
    if (isRejection(e)) onPhase({ phase: 'rejected', message: 'You rejected the transaction in your wallet. Nothing was sent.' });
    else onPhase({ phase: 'failed', message: describeContractError(e) });
    return;
  }
  onPhase({ phase: 'pending', hash });
  try {
    const receipt = await reader.client.waitForTransactionReceipt({ hash, confirmations: 1, timeout: 180_000 });
    if (receipt.status === 'success') onPhase({ phase: 'confirmed', hash, blockNumber: receipt.blockNumber });
    else onPhase({ phase: 'failed', message: 'The transaction was mined but reverted.', hash });
  } catch (e) {
    onPhase({ phase: 'failed', message: `Sent, but confirmation could not be read: ${(e as Error).message}`, hash });
  }
}

/** Turns viem/contract errors into a short human sentence, surfacing the registry's custom error name. */
export function describeContractError(e: unknown): string {
  const err = e as { shortMessage?: string; message?: string; cause?: { data?: { errorName?: string; args?: unknown[] }; shortMessage?: string } };
  const name = err?.cause?.data?.errorName;
  if (name) {
    const args = err.cause?.data?.args ?? [];
    const hints: Record<string, string> = {
      NotChallenger: 'Only the wallet that opened this dispute can withdraw it.',
      DisputeNotOpen: 'This dispute is already withdrawn; it no longer accepts responses or withdrawal.',
      DisputeNotFound: 'No dispute with that id exists on the registry.',
      InvalidTextLength: 'Text must be 1 to 280 UTF-8 bytes.',
      InvalidURILength: 'Evidence URI must be 1 to 512 bytes.',
      ZeroRequestId: 'The request id must not be all zeros.',
      ZeroSourceChainId: 'The source chain id must not be zero.',
      ZeroAttestationSnapshotHash: 'The attestation snapshot hash must not be zero.',
      ZeroEvidenceHash: 'The evidence hash must not be zero.',
    };
    return `${hints[name] ?? `Registry rejected the call with ${name}.`} (${name}${args.length ? `: ${args.map(String).join(', ')}` : ''})`;
  }
  return err?.shortMessage ?? err?.cause?.shortMessage ?? err?.message ?? 'Unknown error';
}
