import { checkEvidenceUri } from '../lib/uri';

/**
 * Renders user-submitted text as text. React escapes it; we additionally normalise control characters so a
 * rationale cannot smuggle bidi overrides or zero-width tricks into the layout.
 */
export function SafeText({ text, className }: { text: string; className?: string }) {
  const cleaned = text.replace(/[\u0000-\u0008\u000b\u000c\u000e-\u001f\u007f​-‏‪-‮⁦-⁩]/g, '');
  return <span className={className}>{cleaned}</span>;
}

/** Only validated https:// and ipfs:// URIs become links; anything else is shown as inert text. */
export function EvidenceLink({ uri }: { uri: string }) {
  const check = checkEvidenceUri(uri);
  if (!check.ok) {
    return (
      <span>
        <code className="break">
          <SafeText text={uri} />
        </code>{' '}
        <span className="badge badge-warn" title={check.reason}>
          not linked: invalid URI
        </span>
      </span>
    );
  }
  return (
    <span>
      <a href={check.href} target="_blank" rel="noopener noreferrer nofollow ugc" className="break">
        {check.display}
      </a>{' '}
      <span className="badge badge-muted">{check.kind === 'ipfs' ? 'IPFS via public gateway' : 'HTTPS'}</span>
    </span>
  );
}
