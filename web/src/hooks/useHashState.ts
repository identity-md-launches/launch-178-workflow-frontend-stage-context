import { useCallback, useEffect, useState } from 'react';

export interface ViewState {
  request: string;
  author: string;
  status: '' | 'open' | 'withdrawn';
  page: number;
  dispute: string; // expanded dispute id, '' for none
  mode: '' | 'live' | 'demo';
}

const DEFAULT: ViewState = { request: '', author: '', status: '', page: 1, dispute: '', mode: '' };

export function parseHash(hash: string): ViewState {
  const q = hash.replace(/^#\/?\??/, '');
  const params = new URLSearchParams(q);
  const status = params.get('status');
  const mode = params.get('mode');
  const page = Number.parseInt(params.get('page') ?? '1', 10);
  return {
    request: params.get('request') ?? '',
    author: params.get('author') ?? '',
    status: status === 'open' || status === 'withdrawn' ? status : '',
    page: Number.isFinite(page) && page > 0 ? page : 1,
    dispute: params.get('dispute') ?? '',
    mode: mode === 'live' || mode === 'demo' ? mode : '',
  };
}

export function serializeHash(state: ViewState): string {
  const params = new URLSearchParams();
  if (state.request) params.set('request', state.request);
  if (state.author) params.set('author', state.author);
  if (state.status) params.set('status', state.status);
  if (state.page > 1) params.set('page', String(state.page));
  if (state.dispute) params.set('dispute', state.dispute);
  if (state.mode) params.set('mode', state.mode);
  const s = params.toString();
  return s ? `#/?${s}` : '#/';
}

/** Filters, pagination, expanded card and data-source mode live in the URL hash (works on static hosting). */
export function useHashState(): [ViewState, (patch: Partial<ViewState>) => void] {
  const [state, setState] = useState<ViewState>(() =>
    typeof window === 'undefined' ? DEFAULT : parseHash(window.location.hash),
  );

  useEffect(() => {
    const onHash = () => setState(parseHash(window.location.hash));
    window.addEventListener('hashchange', onHash);
    return () => window.removeEventListener('hashchange', onHash);
  }, []);

  const update = useCallback((patch: Partial<ViewState>) => {
    setState((prev) => {
      const next = { ...prev, ...patch };
      const hash = serializeHash(next);
      if (typeof window !== 'undefined' && window.location.hash !== hash) {
        window.history.replaceState(null, '', hash);
      }
      return next;
    });
  }, []);

  return [state, update];
}
