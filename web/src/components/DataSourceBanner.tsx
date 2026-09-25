export type DataMode = 'live' | 'demo';

export function DataSourceBanner({
  mode,
  liveError,
  networkName,
  onMode,
}: {
  mode: DataMode;
  liveError: string | null;
  networkName: string;
  onMode: (m: DataMode) => void;
}) {
  if (mode === 'demo') {
    return (
      <div className="notice notice-demo" role="status" aria-live="polite" data-testid="demo-banner">
        <p>
          <strong>Demo mode.</strong> Everything below is synthetic sample data: no wallet connection, no {networkName} reads
          and no IMD API calls. Transaction submission is disabled; nothing here can be submitted as a live dispute.
        </p>
        <button type="button" className="btn btn-sm" onClick={() => onMode('live')}>
          Switch to Live {networkName} Data
        </button>
      </div>
    );
  }
  if (liveError) {
    return (
      <div className="notice notice-danger" role="alert" data-testid="live-error">
        <p>
          <strong>Live data unavailable.</strong> {liveError}
        </p>
        <p className="small">
          The public {networkName} RPCs listed in the deployment configuration could not be read. You can retry, or look at
          the separately labelled demo data (which cannot be submitted).
        </p>
        <button type="button" className="btn btn-sm" onClick={() => onMode('demo')}>
          Open Demo Mode
        </button>
      </div>
    );
  }
  return (
    <p className="small muted" data-testid="live-banner">
      Reading the live {networkName} registry through public RPCs.{' '}
      <button type="button" className="btn-link" onClick={() => onMode('demo')}>
        Show demo data instead
      </button>
    </p>
  );
}
