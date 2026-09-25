import { keccak256, toBytes, type Abi, type Address } from 'viem';
import { DEPLOYMENT_MANIFEST_PATH } from '../config';

export interface ManifestContract {
  name: string;
  address: Address;
  abiHash: string;
  abiPath: string;
}

export interface ManifestAsset {
  path: string;
  sha256: string;
}

export interface NetworkConfig {
  chainId: number;
  name: string;
  testnet: boolean;
  rpcUrls: string[];
  explorer: string;
  nativeCurrency: { name: string; symbol: string; decimals: number };
  faucets?: string[];
  uniswapV4?: Record<string, string>;
}

export interface DeploymentManifest {
  version: 1;
  launchId: string;
  chainId: number;
  sourceCommit: string;
  attestationHash: string;
  contracts: ManifestContract[];
  assets: ManifestAsset[];
  network: NetworkConfig;
}

export interface LoadedContract extends ManifestContract {
  abi: Abi;
  /** canonical keccak256 (sorted keys, compact JSON) of the loaded ABI, without 0x */
  computedAbiHash: string;
  abiHashMatches: boolean;
}

export interface Deployment {
  manifest: DeploymentManifest;
  contracts: Record<string, LoadedContract>;
  registry: LoadedContract;
  token: LoadedContract;
  network: NetworkConfig;
}

export const REGISTRY_CONTRACT_NAME = 'IMDOracleDisputeRegistry';
export const TOKEN_CONTRACT_NAME = 'OracleChallengeToken';

const HEX64 = /^[0-9a-f]{64}$/;
const ADDRESS = /^0x[0-9a-fA-F]{40}$/;

/** Canonical JSON: recursively sorted object keys, no insignificant whitespace. */
export function canonicalJson(value: unknown): string {
  if (Array.isArray(value)) return `[${value.map(canonicalJson).join(',')}]`;
  if (value !== null && typeof value === 'object') {
    const record = value as Record<string, unknown>;
    return `{${Object.keys(record)
      .sort()
      .map((k) => `${JSON.stringify(k)}:${canonicalJson(record[k])}`)
      .join(',')}}`;
  }
  return JSON.stringify(value);
}

/** keccak256 of the canonical JSON encoding, as 64 lowercase hex characters without 0x. */
export function canonicalKeccak(value: unknown): string {
  return keccak256(toBytes(canonicalJson(value))).slice(2);
}

function isSafeRelativePath(p: string): boolean {
  if (typeof p !== 'string' || p.length === 0) return false;
  if (p.startsWith('/') || p.includes('://') || p.startsWith('\\')) return false;
  return !p.split('/').some((seg) => seg === '..' || seg === '');
}

export function validateManifest(input: unknown): DeploymentManifest {
  if (!input || typeof input !== 'object') throw new Error('deployment manifest is not an object');
  const m = input as Record<string, unknown>;
  if (m.version !== 1) throw new Error(`unsupported manifest version ${String(m.version)}`);
  if (typeof m.launchId !== 'string' || !m.launchId) throw new Error('manifest launchId missing');
  if (typeof m.chainId !== 'number' || !Number.isInteger(m.chainId) || m.chainId <= 0) {
    throw new Error('manifest chainId invalid');
  }
  if (typeof m.sourceCommit !== 'string' || !/^[0-9a-f]{40}$/.test(m.sourceCommit)) {
    throw new Error('manifest sourceCommit invalid');
  }
  if (typeof m.attestationHash !== 'string' || !HEX64.test(m.attestationHash)) {
    throw new Error('manifest attestationHash invalid');
  }
  if (!Array.isArray(m.contracts) || m.contracts.length === 0) throw new Error('manifest contracts missing');
  const contracts = m.contracts.map((c: unknown) => {
    const r = c as Record<string, unknown>;
    if (typeof r.name !== 'string' || !r.name) throw new Error('contract name missing');
    if (typeof r.address !== 'string' || !ADDRESS.test(r.address)) throw new Error(`bad address for ${r.name}`);
    if (typeof r.abiHash !== 'string' || !HEX64.test(r.abiHash)) throw new Error(`bad abiHash for ${r.name}`);
    if (typeof r.abiPath !== 'string' || !isSafeRelativePath(r.abiPath)) {
      throw new Error(`bad abiPath for ${r.name}`);
    }
    return { name: r.name, address: r.address as Address, abiHash: r.abiHash, abiPath: r.abiPath };
  });
  if (!Array.isArray(m.assets)) throw new Error('manifest assets missing');
  const assets = m.assets.map((a: unknown) => {
    const r = a as Record<string, unknown>;
    if (typeof r.path !== 'string' || !isSafeRelativePath(r.path)) throw new Error('bad asset path');
    if (typeof r.sha256 !== 'string' || !HEX64.test(r.sha256)) throw new Error(`bad sha256 for ${r.path}`);
    return { path: r.path, sha256: r.sha256 };
  });
  const n = m.network as Record<string, unknown> | undefined;
  if (!n || typeof n !== 'object') throw new Error('manifest network missing');
  if (n.chainId !== m.chainId) throw new Error('manifest network.chainId differs from chainId');
  if (typeof n.name !== 'string') throw new Error('network name missing');
  if (!Array.isArray(n.rpcUrls) || n.rpcUrls.length === 0) throw new Error('network rpcUrls missing');
  for (const u of n.rpcUrls) {
    if (typeof u !== 'string' || !/^https:\/\//.test(u)) throw new Error(`rpc url must be https: ${String(u)}`);
  }
  if (typeof n.explorer !== 'string') throw new Error('network explorer missing');
  const nc = n.nativeCurrency as Record<string, unknown> | undefined;
  if (!nc || typeof nc.symbol !== 'string' || typeof nc.decimals !== 'number' || typeof nc.name !== 'string') {
    throw new Error('network nativeCurrency invalid');
  }
  return {
    version: 1,
    launchId: m.launchId,
    chainId: m.chainId,
    sourceCommit: m.sourceCommit,
    attestationHash: m.attestationHash,
    contracts,
    assets,
    network: {
      chainId: n.chainId,
      name: n.name,
      testnet: Boolean(n.testnet),
      rpcUrls: n.rpcUrls as string[],
      explorer: n.explorer,
      nativeCurrency: { name: nc.name, symbol: nc.symbol, decimals: nc.decimals },
      faucets: Array.isArray(n.faucets) ? (n.faucets as string[]) : undefined,
      uniswapV4:
        n.uniswapV4 && typeof n.uniswapV4 === 'object' ? (n.uniswapV4 as Record<string, string>) : undefined,
    },
  };
}

export type Fetcher = (input: string) => Promise<Response>;

async function fetchJson(fetcher: Fetcher, url: string): Promise<unknown> {
  const res = await fetcher(url);
  if (!res.ok) throw new Error(`${url}: HTTP ${res.status}`);
  return res.json();
}

/**
 * Loads ./imd-deployment.json and every ABI it references. Throws when the manifest is malformed, an ABI is
 * missing, or an ABI's canonical keccak256 does not match the attested abiHash (transactions must not be
 * enabled against an ABI that does not match the handoff).
 */
export async function loadDeployment(
  fetcher: Fetcher = (u) => fetch(u, { cache: 'no-cache' }),
  manifestPath: string = DEPLOYMENT_MANIFEST_PATH,
): Promise<Deployment> {
  const manifest = validateManifest(await fetchJson(fetcher, manifestPath));
  const contracts: Record<string, LoadedContract> = {};
  for (const c of manifest.contracts) {
    const abi = await fetchJson(fetcher, `./${c.abiPath}`);
    if (!Array.isArray(abi)) throw new Error(`${c.abiPath} is not an ABI array`);
    const computedAbiHash = canonicalKeccak(abi);
    const abiHashMatches = computedAbiHash === c.abiHash;
    if (!abiHashMatches) {
      throw new Error(`ABI hash mismatch for ${c.name}: ${computedAbiHash} != ${c.abiHash}`);
    }
    contracts[c.name] = { ...c, abi: abi as Abi, computedAbiHash, abiHashMatches };
  }
  const registry = contracts[REGISTRY_CONTRACT_NAME];
  const token = contracts[TOKEN_CONTRACT_NAME];
  if (!registry) throw new Error(`manifest has no ${REGISTRY_CONTRACT_NAME} contract`);
  if (!token) throw new Error(`manifest has no ${TOKEN_CONTRACT_NAME} contract`);
  return { manifest, contracts, registry, token, network: manifest.network };
}

/** wallet_addEthereumChain parameters derived from the manifest's network block (single source of truth). */
export function walletAddChainParams(network: NetworkConfig) {
  return {
    chainId: `0x${network.chainId.toString(16)}`,
    chainName: network.name,
    rpcUrls: network.rpcUrls,
    nativeCurrency: network.nativeCurrency,
    blockExplorerUrls: [network.explorer],
  };
}

export const explorerAddressUrl = (network: NetworkConfig, address: string) =>
  `${network.explorer.replace(/\/$/, '')}/address/${address}`;
export const explorerTxUrl = (network: NetworkConfig, hash: string) =>
  `${network.explorer.replace(/\/$/, '')}/tx/${hash}`;
