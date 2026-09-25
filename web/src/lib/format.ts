import { formatUnits } from 'viem';

export const shortAddress = (a: string): string => (a.length > 12 ? `${a.slice(0, 6)}…${a.slice(-4)}` : a);

export const shortHash = (h: string): string => (h.length > 18 ? `${h.slice(0, 10)}…${h.slice(-6)}` : h);

const dateTime = new Intl.DateTimeFormat(undefined, { dateStyle: 'medium', timeStyle: 'short', timeZone: 'UTC' });

/** Unix seconds -> localized UTC date/time string. */
export function formatUnixSeconds(seconds: bigint | number): string {
  const ms = Number(seconds) * 1000;
  if (!Number.isFinite(ms) || ms <= 0) return '—';
  return `${dateTime.format(new Date(ms))} UTC`;
}

export function formatIso(iso: string | null | undefined): string {
  if (!iso) return '—';
  const d = new Date(iso);
  return Number.isNaN(d.getTime()) ? iso : `${dateTime.format(d)} UTC`;
}

const integer = new Intl.NumberFormat(undefined, { maximumFractionDigits: 0 });
const decimal = new Intl.NumberFormat(undefined, { maximumFractionDigits: 4 });

export function formatInteger(n: number | bigint): string {
  return integer.format(typeof n === 'bigint' ? n : Math.trunc(n));
}

/** Token amount in whole units using the token's own decimals. */
export function formatTokenAmount(amount: bigint, decimals: number, symbol: string): string {
  const units = formatUnits(amount, decimals);
  const [whole, frac] = units.split('.');
  const wholeFormatted = integer.format(BigInt(whole ?? '0'));
  const fracTrimmed = (frac ?? '').replace(/0+$/, '');
  const text = fracTrimmed ? `${wholeFormatted}.${fracTrimmed.slice(0, 4)}` : wholeFormatted;
  return `${text} ${symbol}`;
}

export function formatBytes(n: number): string {
  if (n < 1024) return `${n} B`;
  if (n < 1024 * 1024) return `${decimal.format(n / 1024)} KiB`;
  return `${decimal.format(n / (1024 * 1024))} MiB`;
}

export function sameAddress(a?: string | null, b?: string | null): boolean {
  return Boolean(a && b && a.toLowerCase() === b.toLowerCase());
}
