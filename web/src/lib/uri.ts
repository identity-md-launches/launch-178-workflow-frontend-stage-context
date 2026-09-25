import { IPFS_GATEWAY, MAX_URI_BYTES } from '../config';

export type UriCheck =
  | { ok: true; kind: 'https' | 'ipfs'; href: string; display: string }
  | { ok: false; reason: string };

const encoder = new TextEncoder();

export function utf8ByteLength(text: string): number {
  return encoder.encode(text).length;
}

/**
 * Validates an evidence URI for linking. Only `https://` URLs and `ipfs://<cid>[/path]` are ever turned into
 * links; everything else (including javascript:, data:, http:) is rendered as plain text.
 */
export function checkEvidenceUri(raw: string): UriCheck {
  const value = raw.trim();
  if (!value) return { ok: false, reason: 'Enter an HTTPS or IPFS URI.' };
  const bytes = utf8ByteLength(value);
  if (bytes > MAX_URI_BYTES) {
    return { ok: false, reason: `URI is ${bytes} bytes; the registry allows at most ${MAX_URI_BYTES}.` };
  }
  if (/\s/.test(value)) return { ok: false, reason: 'URI must not contain whitespace.' };

  if (/^ipfs:\/\//i.test(value)) {
    const rest = value.slice('ipfs://'.length);
    const m = /^([A-Za-z0-9]{46,128})(\/[A-Za-z0-9._~!$&'()*+,;=:@%/-]*)?$/.exec(rest);
    if (!m) return { ok: false, reason: 'IPFS URI must look like ipfs://<CID>/optional/path.' };
    const cid = m[1]!;
    const path = m[2] ?? '';
    return { ok: true, kind: 'ipfs', href: `${IPFS_GATEWAY}${cid}${path}`, display: `ipfs://${cid}${path}` };
  }

  let url: URL;
  try {
    url = new URL(value);
  } catch {
    return { ok: false, reason: 'Not a valid URL. Use https://host/path or ipfs://CID.' };
  }
  if (url.protocol !== 'https:') return { ok: false, reason: 'Only https:// and ipfs:// URIs are accepted.' };
  if (!url.hostname || !url.hostname.includes('.')) return { ok: false, reason: 'HTTPS URI needs a hostname.' };
  if (url.username || url.password) return { ok: false, reason: 'Credentials in URLs are not allowed.' };
  return { ok: true, kind: 'https', href: url.href, display: value };
}

export function checkText(text: string, maxBytes: number): { ok: boolean; bytes: number; reason?: string } {
  const bytes = utf8ByteLength(text);
  if (bytes === 0) return { ok: false, bytes, reason: 'Enter some text.' };
  if (bytes > maxBytes) return { ok: false, bytes, reason: `${bytes} bytes; the registry allows at most ${maxBytes}.` };
  return { ok: true, bytes };
}
