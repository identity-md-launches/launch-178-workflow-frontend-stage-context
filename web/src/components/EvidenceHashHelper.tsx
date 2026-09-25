import { useId, useState } from 'react';
import { keccak256, type Hex } from 'viem';
import { formatBytes } from '../lib/format';

const HEX32 = /^0x[0-9a-fA-F]{64}$/;

export interface EvidenceHashValue {
  hash: Hex | '';
  source: 'file' | 'manual' | '';
  fileName?: string;
  fileSize?: number;
}

/**
 * keccak256 over the raw bytes of a local file, computed in the browser. The file is never uploaded, hosted or
 * stored by this site; the user must host it themselves at the evidence URI.
 */
export function EvidenceHashHelper({ value, onChange, label }: { value: EvidenceHashValue; onChange: (v: EvidenceHashValue) => void; label: string }) {
  const fileId = useId();
  const manualId = useId();
  const [busy, setBusy] = useState(false);
  const [fileError, setFileError] = useState<string | null>(null);
  const manualInvalid = value.source === 'manual' && value.hash !== '' && !HEX32.test(value.hash);

  const onFile = async (file: File | undefined) => {
    setFileError(null);
    if (!file) return;
    setBusy(true);
    try {
      const bytes = new Uint8Array(await file.arrayBuffer());
      const hash = keccak256(bytes);
      onChange({ hash, source: 'file', fileName: file.name, fileSize: bytes.length });
    } catch (e) {
      setFileError(`Could not read the file: ${(e as Error).message}`);
    } finally {
      setBusy(false);
    }
  };

  return (
    <fieldset>
      <legend>{label}</legend>
      <p className="hint small muted">
        Choose the evidence file to compute <code>keccak256</code> over its raw bytes in your browser. Choosing a file{' '}
        <strong>does not upload or host it</strong>; host it yourself and put that location in the evidence URI field.
      </p>
      <div className="stack">
        <div className="field">
          <label htmlFor={fileId}>Evidence file (hashed locally)</label>
          <input id={fileId} type="file" name="evidence-file" onChange={(e) => void onFile(e.target.files?.[0])} disabled={busy} />
          {busy && (
            <p className="hint">
              <span className="spinner" aria-hidden="true" /> Hashing…
            </p>
          )}
          {value.source === 'file' && value.fileName && (
            <p className="hint" aria-live="polite">
              Hashed <code translate="no">{value.fileName}</code> ({formatBytes(value.fileSize ?? 0)}).
            </p>
          )}
          {fileError && (
            <p className="error" role="alert">
              {fileError}
            </p>
          )}
        </div>
        <div className="field">
          <label htmlFor={manualId}>Or paste an existing keccak256 (0x + 64 hex)</label>
          <input
            id={manualId}
            type="text"
            name="evidence-hash"
            inputMode="text"
            autoComplete="off"
            spellCheck={false}
            placeholder="0x…"
            value={value.hash}
            aria-invalid={manualInvalid || undefined}
            aria-describedby={manualInvalid ? `${manualId}-err` : undefined}
            onChange={(e) => onChange({ hash: e.target.value as Hex | '', source: 'manual' })}
          />
          {manualInvalid && (
            <p id={`${manualId}-err`} className="error">
              Enter 0x followed by exactly 64 hex characters, or choose a file above.
            </p>
          )}
        </div>
      </div>
    </fieldset>
  );
}

export const isValidHash32 = (h: string): h is Hex => HEX32.test(h) && !/^0x0{64}$/.test(h);
