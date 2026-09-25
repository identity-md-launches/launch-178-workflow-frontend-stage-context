import type { Hex } from 'viem';

const UUID_RE = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

/** True for a complete, hyphenated 36-character UUID. */
export function isCompleteUuid(value: string): boolean {
  return UUID_RE.test(value.trim());
}

/** Normalises a UUID to lowercase hyphenated form, or returns null. */
export function normalizeUuid(value: string): string | null {
  const v = value.trim().toLowerCase();
  return UUID_RE.test(v) ? v : null;
}

/** IMD request UUID -> bytes16 (the 16 bytes of its hex digits with hyphens removed). */
export function uuidToBytes16(uuid: string): Hex {
  const v = normalizeUuid(uuid);
  if (!v) throw new Error('not a complete UUID');
  const hex = v.replace(/-/g, '');
  if (/^0+$/.test(hex)) throw new Error('the all-zero UUID is not a valid request id');
  return `0x${hex}`;
}

/** bytes16 hex (0x + 32 hex chars) -> hyphenated UUID; falls back to the raw hex if malformed. */
export function bytes16ToUuid(value: string): string {
  const hex = value.toLowerCase().replace(/^0x/, '');
  if (!/^[0-9a-f]{32}$/.test(hex)) return value;
  return `${hex.slice(0, 8)}-${hex.slice(8, 12)}-${hex.slice(12, 16)}-${hex.slice(16, 20)}-${hex.slice(20)}`;
}

/** Left-aligned bytes32 (as the attestation message encodes requestId) -> UUID. */
export function bytes32ToUuid(value: string): string {
  const hex = value.toLowerCase().replace(/^0x/, '');
  if (!/^[0-9a-f]{64}$/.test(hex)) return value;
  return bytes16ToUuid(hex.slice(0, 32));
}
