import { useState, useCallback, useEffect, useRef } from 'react';

function withInitialStatus(checks) {
  return checks.map((check) => ({
    ...check,
    status: 'Pending',
    message: check.message || 'Not started.',
  }));
}

export function usePrerequisites() {
  const [checks, setChecks] = useState([]);
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState(null);
  const sourceRef = useRef(null);

  const loadChecks = useCallback(async () => {
    const res = await fetch('/api/prerequisites/checks');
    if (!res.ok) throw new Error(`Failed to load prerequisites list: ${res.status}`);
    const data = await res.json();
    setChecks(withInitialStatus(data));
  }, []);

  useEffect(() => {
    loadChecks().catch((err) => setError(err.message));

    return () => {
      if (sourceRef.current) {
        sourceRef.current.close();
      }
    };
  }, [loadChecks]);

  const runCheck = useCallback(async () => {
    if (sourceRef.current) {
      sourceRef.current.close();
      sourceRef.current = null;
    }

    setLoading(true);
    setError(null);
    setChecks((current) => current.map((item) => ({ ...item, status: 'Running', message: 'Running check...' })));

    const source = new EventSource('/api/prerequisites/stream');
    sourceRef.current = source;

    source.addEventListener('start', (event) => {
      const payload = JSON.parse(event.data);
      setChecks(withInitialStatus(payload.checks || []));
      setChecks((current) => current.map((item) => ({ ...item, status: 'Running', message: 'Running check...' })));
    });

    source.addEventListener('update', (event) => {
      const payload = JSON.parse(event.data);
      setChecks((current) =>
        current.map((item) => (item.name === payload.name ? { ...item, ...payload } : item)),
      );
    });

    source.addEventListener('complete', (event) => {
      const payload = JSON.parse(event.data);
      setChecks(payload.results || []);
      setLoading(false);
      source.close();
      sourceRef.current = null;
    });

    source.addEventListener('error', (event) => {
      let message = 'Prerequisites check failed.';
      if (event?.data) {
        try {
          message = JSON.parse(event.data).error || message;
        } catch {
          message = event.data || message;
        }
      }

      setError(message);
      setLoading(false);
      source.close();
      sourceRef.current = null;
    });
  }, []);

  const remediateCheck = useCallback(async (name) => {
    const res = await fetch('/api/prerequisites/remediate', {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
      },
      body: JSON.stringify({ name }),
    });

    const payload = await res.json().catch(() => ({}));
    if (!res.ok) {
      const details = payload?.details ? ` ${payload.details}` : '';
      throw new Error(`${payload?.error || `Failed to remediate '${name}'.`}${details}`);
    }

    return payload;
  }, []);

  return { checks, loading, error, runCheck, remediateCheck };
}
