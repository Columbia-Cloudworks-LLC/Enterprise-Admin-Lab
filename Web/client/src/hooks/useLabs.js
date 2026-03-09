import { useState, useEffect, useCallback } from 'react';

const API = '/api';

export function useLabs() {
  const [labs, setLabs] = useState([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState(null);

  const fetchLabs = useCallback(async () => {
    setLoading(true);
    setError(null);
    try {
      const res = await fetch(`${API}/labs`);
      if (!res.ok) throw new Error(`Failed to fetch labs: ${res.status}`);
      const data = await res.json();
      setLabs(data);
    } catch (err) {
      setError(err.message);
    } finally {
      setLoading(false);
    }
  }, []);

  useEffect(() => {
    fetchLabs();
  }, [fetchLabs]);

  useEffect(() => {
    const hasActiveOperations = labs.some((lab) => ['Creating', 'Destroying'].includes(lab.status));
    if (!hasActiveOperations) {
      return undefined;
    }

    const timer = setInterval(() => {
      fetchLabs();
    }, 5000);

    return () => clearInterval(timer);
  }, [labs, fetchLabs]);

  return { labs, loading, error, refetch: fetchLabs };
}

export function useLab(name) {
  const [lab, setLab] = useState(null);
  const [loading, setLoading] = useState(!!name);
  const [error, setError] = useState(null);

  useEffect(() => {
    if (!name) {
      setLab(null);
      setLoading(false);
      return;
    }

    let cancelled = false;
    setLoading(true);
    setError(null);

    fetch(`${API}/labs/${encodeURIComponent(name)}`)
      .then((res) => {
        if (!res.ok) throw new Error(`Lab not found: ${res.status}`);
        return res.json();
      })
      .then((data) => {
        if (!cancelled) setLab(data);
      })
      .catch((err) => {
        if (!cancelled) setError(err.message);
      })
      .finally(() => {
        if (!cancelled) setLoading(false);
      });

    return () => {
      cancelled = true;
    };
  }, [name]);

  return { lab, loading, error };
}

export async function saveLab(config, { isNew = true, originalName = '' } = {}) {
  const url = isNew ? `${API}/labs` : `${API}/labs/${encodeURIComponent(originalName)}`;
  const method = isNew ? 'POST' : 'PUT';

  const res = await fetch(url, {
    method,
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify(config),
  });

  return res.json();
}

export async function deleteLab(name) {
  const res = await fetch(`${API}/labs/${encodeURIComponent(name)}`, {
    method: 'DELETE',
  });
  return readJsonOrThrow(res, 'Failed to delete lab');
}

async function readJsonOrThrow(res, fallbackMessage) {
  let payload = {};
  try {
    payload = await res.json();
  } catch {
    payload = {};
  }

  if (!res.ok) {
    const message = payload.error || payload.message || fallbackMessage || `Request failed: ${res.status}`;
    const error = new Error(message);
    error.details = payload;
    throw error;
  }
  return payload;
}

export async function launchLab(name, { skipOrchestration = false } = {}) {
  const res = await fetch(`${API}/labs/${encodeURIComponent(name)}/launch`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ skipOrchestration }),
  });
  return readJsonOrThrow(res, 'Failed to launch lab');
}

export async function destroyLabEnvironment(name, { deleteLabData = false } = {}) {
  const res = await fetch(`${API}/labs/${encodeURIComponent(name)}/destroy`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ deleteLabData }),
  });
  return readJsonOrThrow(res, 'Failed to destroy lab resources');
}

export async function fetchLabStatus(name) {
  const res = await fetch(`${API}/labs/${encodeURIComponent(name)}/status`);
  return readJsonOrThrow(res, 'Failed to fetch lab status');
}

export async function testCredentialRefs(refs) {
  const normalizedRefs = Array.isArray(refs) ? refs.map((value) => String(value || '').trim()).filter(Boolean) : [];
  const params = new URLSearchParams();
  params.set('refs', normalizedRefs.join(','));
  const res = await fetch(`${API}/credentials/status?${params.toString()}`);
  return readJsonOrThrow(res, 'Failed to validate credential refs');
}

export async function setCredentialRef({ target, username, password, provider = 'Auto' }) {
  const res = await fetch(`${API}/credentials`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({
      target,
      username,
      password,
      provider,
    }),
  });
  return readJsonOrThrow(res, 'Failed to set credential ref');
}

export async function fetchDefaults() {
  const res = await fetch(`${API}/defaults`);
  if (!res.ok) throw new Error(`Failed to fetch defaults: ${res.status}`);
  return res.json();
}
