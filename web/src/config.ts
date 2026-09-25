// Central, public, non-secret configuration.
//
// Contract addresses, the registry chain id, ABIs and public RPC URLs are NOT defined here: the app loads them
// at runtime from ./imd-deployment.json (written by scripts/write-manifest.mjs from the attested workflow
// handoff) so there is exactly one deployment configuration and nothing that can silently disagree with it.
// See src/lib/deployment.ts.

/** Relative path of the runtime deployment configuration (relative to index.html). */
export const DEPLOYMENT_MANIFEST_PATH = './imd-deployment.json';

/** Public IMD oracle API (read-only, no key). Only used to show what IMD published about a request. */
export const IMD_API_BASE = 'https://api.imd.fun';

export const imdRequestUrl = (id: string) => `${IMD_API_BASE}/oracle/requests/${encodeURIComponent(id)}`;
export const imdAttestationUrl = (id: string) => `${imdRequestUrl(id)}/attestation`;

/** Public IPFS gateway used only to turn validated ipfs:// URIs into clickable links. */
export const IPFS_GATEWAY = 'https://ipfs.io/ipfs/';

/** Items per page in the browse view (client-side pages over registry reads of up to MAX_PAGE_LIMIT). */
export const PAGE_SIZE = 10;

/** Registry constants (also exposed on-chain as MAX_TEXT_BYTES / MAX_URI_BYTES / MAX_PAGE_LIMIT). */
export const MAX_TEXT_BYTES = 280;
export const MAX_URI_BYTES = 512;
export const MAX_PAGE_LIMIT = 50;

/** Safety cap on how many disputes the browser will page through in one load. */
export const MAX_DISPUTES_LOADED = 2000;

/**
 * Reference names for source chains an oracle request may be *about*. Display only; the registry stores the
 * challenger's claimed sourceChainId verbatim and this app never transacts on these chains.
 */
export const SOURCE_CHAIN_NAMES: Record<number, { name: string; explorer?: string }> = {
  1: { name: 'Ethereum mainnet', explorer: 'https://etherscan.io' },
  10: { name: 'OP Mainnet', explorer: 'https://optimistic.etherscan.io' },
  56: { name: 'BNB Smart Chain', explorer: 'https://bscscan.com' },
  137: { name: 'Polygon PoS', explorer: 'https://polygonscan.com' },
  8453: { name: 'Base', explorer: 'https://basescan.org' },
  42161: { name: 'Arbitrum One', explorer: 'https://arbiscan.io' },
  11155111: { name: 'Sepolia testnet', explorer: 'https://sepolia.etherscan.io' },
};

export const sourceChainLabel = (chainId: number | bigint): string => {
  const id = Number(chainId);
  const known = SOURCE_CHAIN_NAMES[id];
  return known ? `${known.name} (chain ${id})` : `chain ${id}`;
};
