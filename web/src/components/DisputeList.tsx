import { useId, type ReactNode } from 'react';
import { PAGE_SIZE } from '../config';
import type { ViewState } from '../hooks/useHashState';
import type { NetworkConfig } from '../lib/deployment';
import type { Dispute } from '../lib/registry';
import { bytes16ToUuid, normalizeUuid } from '../lib/uuid';
import { DisputeCard } from './DisputeCard';

export type DisputesState =
  | { status: 'loading'; loaded: number; total: number }
  | { status: 'ready'; disputes: Dispute[]; total: bigint; truncated: boolean }
  | { status: 'error'; message: string };

export function applyFilters(disputes: Dispute[], view: ViewState): Dispute[] {
  const req = normalizeUuid(view.request) ?? view.request.trim().toLowerCase();
  const author = view.author.trim().toLowerCase();
  return disputes.filter((d) => {
    if (req && !bytes16ToUuid(d.requestId).includes(req)) return false;
    if (author && !d.challenger.toLowerCase().includes(author)) return false;
    if (view.status === 'open' && d.status !== 0) return false;
    if (view.status === 'withdrawn' && d.status !== 1) return false;
    return true;
  });
}

export function paginate<T>(items: T[], page: number, size: number): { items: T[]; page: number; pages: number } {
  const pages = Math.max(1, Math.ceil(items.length / size));
  const p = Math.min(Math.max(1, page), pages);
  return { items: items.slice((p - 1) * size, p * size), page: p, pages };
}

export function DisputeList({
  state,
  view,
  onView,
  network,
  demo,
  onRetry,
  renderDetail,
}: {
  state: DisputesState;
  view: ViewState;
  onView: (patch: Partial<ViewState>) => void;
  network: NetworkConfig;
  demo: boolean;
  onRetry: () => void;
  renderDetail: (d: Dispute) => ReactNode;
}) {
  const reqId = useId();
  const authorId = useId();
  const statusId = useId();

  const filtered = state.status === 'ready' ? applyFilters([...state.disputes].reverse(), view) : [];
  const pageData = paginate(filtered, view.page, PAGE_SIZE);
  const hasFilters = Boolean(view.request || view.author || view.status);

  return (
    <section className="block" aria-labelledby="browse-heading">
      <h2 id="browse-heading">
        Browse Challenges
        {state.status === 'ready' && (
          <span className="badge badge-muted num">
            {state.total.toString()} on the {demo ? 'demo' : network.name} registry
          </span>
        )}
      </h2>
      <p className="small muted">
        Newest first. Every entry is an unproven claim by the wallet that submitted it; statuses are only Open or Withdrawn.
        Read-only: no wallet needed.
      </p>
      <form className="filters" role="search" onSubmit={(e) => e.preventDefault()} aria-label="Filter challenges">
        <div className="field">
          <label htmlFor={reqId}>Request UUID</label>
          <input
            id={reqId}
            type="search"
            name="request"
            autoComplete="off"
            spellCheck={false}
            placeholder="0192d5f8-…"
            value={view.request}
            onChange={(e) => onView({ request: e.target.value, page: 1 })}
          />
        </div>
        <div className="field">
          <label htmlFor={authorId}>Challenger address</label>
          <input
            id={authorId}
            type="search"
            name="author"
            autoComplete="off"
            spellCheck={false}
            placeholder="0xabc…"
            value={view.author}
            onChange={(e) => onView({ author: e.target.value, page: 1 })}
          />
        </div>
        <div className="field">
          <label htmlFor={statusId}>Status</label>
          <select id={statusId} name="status" value={view.status} onChange={(e) => onView({ status: e.target.value as ViewState['status'], page: 1 })}>
            <option value="">All</option>
            <option value="open">Open</option>
            <option value="withdrawn">Withdrawn</option>
          </select>
        </div>
        <div className="field">
          <span className="label" aria-hidden="true">
            &nbsp;
          </span>
          <button type="button" className="btn" onClick={() => onView({ request: '', author: '', status: '', page: 1 })} disabled={!hasFilters}>
            Clear Filters
          </button>
        </div>
      </form>

      <div aria-live="polite" aria-busy={state.status === 'loading'}>
        {state.status === 'loading' && (
          <div className="card" role="status" data-testid="disputes-loading">
            <span className="spinner" aria-hidden="true" /> Loading challenges from {network.name}…{' '}
            {state.total > 0 && (
              <span className="num">
                {state.loaded}/{state.total}
              </span>
            )}
          </div>
        )}
        {state.status === 'error' && (
          <div className="notice notice-danger" role="alert" data-testid="disputes-error">
            <p>Could not read the registry: {state.message}</p>
            <button type="button" className="btn btn-sm" onClick={onRetry}>
              Retry
            </button>
          </div>
        )}
        {state.status === 'ready' && state.disputes.length === 0 && (
          <div className="card" data-testid="disputes-empty">
            <p style={{ margin: 0 }}>
              No challenges have been recorded on the {demo ? 'demo' : network.name} registry yet. Open the first one below.
            </p>
          </div>
        )}
        {state.status === 'ready' && state.disputes.length > 0 && filtered.length === 0 && (
          <div className="card" data-testid="disputes-nomatch">
            <p style={{ margin: 0 }}>No challenges match these filters.</p>
          </div>
        )}
        {state.status === 'ready' && state.truncated && (
          <p className="small muted">Showing the first {state.disputes.length} of {state.total.toString()} disputes (load cap).</p>
        )}
        {pageData.items.map((d) => (
          <DisputeCard
            key={d.id.toString()}
            dispute={d}
            network={network}
            demo={demo}
            expanded={view.dispute === d.id.toString()}
            onToggle={() => onView({ dispute: view.dispute === d.id.toString() ? '' : d.id.toString() })}
          >
            {view.dispute === d.id.toString() && renderDetail(d)}
          </DisputeCard>
        ))}
      </div>

      {state.status === 'ready' && filtered.length > PAGE_SIZE && (
        <nav className="pager" aria-label="Pagination">
          <button type="button" className="btn btn-sm" onClick={() => onView({ page: pageData.page - 1 })} disabled={pageData.page <= 1}>
            Previous Page
          </button>
          <span className="num small">
            Page {pageData.page} of {pageData.pages} · {filtered.length} matching
          </span>
          <button type="button" className="btn btn-sm" onClick={() => onView({ page: pageData.page + 1 })} disabled={pageData.page >= pageData.pages}>
            Next Page
          </button>
        </nav>
      )}
    </section>
  );
}
