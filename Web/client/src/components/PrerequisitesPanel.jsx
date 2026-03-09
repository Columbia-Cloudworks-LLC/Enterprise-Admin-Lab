import { useState } from 'react';
import { usePrerequisites } from '../hooks/usePrerequisites.js';
import StatusBadge from './StatusBadge.jsx';

function toBadgeStatus(status) {
  if (status === 'Passed') return 'pass';
  if (status === 'Warning') return 'warning';
  if (status === 'Failed') return 'fail';
  if (status === 'Running') return 'info';
  return 'neutral';
}

export default function PrerequisitesPanel() {
  const { checks, loading, error, runCheck, remediateCheck } = usePrerequisites();
  const [copiedCheck, setCopiedCheck] = useState('');
  const [installingCheck, setInstallingCheck] = useState('');
  const [actionMessage, setActionMessage] = useState('');
  const [actionError, setActionError] = useState('');
  const failedCount = checks.filter((item) => item.status === 'Failed').length;
  const warningCount = checks.filter((item) => item.status === 'Warning').length;
  const passedCount = checks.filter((item) => item.status === 'Passed').length;
  const runningCount = checks.filter((item) => item.status === 'Running').length;
  const pendingCount = checks.filter((item) => item.status === 'Pending').length;
  const totalChecks = checks.length;
  const allFinalized = totalChecks > 0 && checks.every((item) => ['Passed', 'Failed', 'Warning'].includes(item.status));

  const handleCopyCommand = async (name, command) => {
    if (!command) {
      return;
    }

    try {
      await navigator.clipboard.writeText(command);
      setCopiedCheck(name);
      window.setTimeout(() => {
        setCopiedCheck((current) => (current === name ? '' : current));
      }, 1500);
    } catch {
      setCopiedCheck('');
    }
  };

  const handleInstall = async (name) => {
    if (!name) {
      return;
    }

    setActionError('');
    setActionMessage('');
    setInstallingCheck(name);
    try {
      const result = await remediateCheck(name);
      setActionMessage(result?.message || `Remediation executed for '${name}'.`);
      await runCheck();
    } catch (installError) {
      setActionError(installError.message || `Failed to remediate '${name}'.`);
    } finally {
      setInstallingCheck('');
    }
  };

  return (
    <div>
      <div className="flex items-center justify-between mb-6">
        <h2 className="text-xl font-bold text-gray-800">Prerequisites Check</h2>
        <button
          onClick={runCheck}
          disabled={loading}
          className="px-4 py-2 bg-[#007ACC] text-white rounded-md text-sm font-medium hover:bg-[#005A9C] disabled:opacity-50 transition-colors"
        >
          {loading ? (
            <span className="flex items-center gap-2">
              <span className="spinner" /> Running...
            </span>
          ) : (
            'Run Check'
          )}
        </button>
      </div>

      <div className="bg-white rounded-lg border border-gray-200 overflow-hidden mb-6">
        <div className="p-4 border-b border-gray-200 bg-gray-50 flex flex-wrap items-center gap-3">
          <span className="font-medium text-gray-700">Summary:</span>
          <StatusBadge status="pass" label={`${passedCount} passed`} />
          <StatusBadge status="warning" label={`${warningCount} warning`} />
          <StatusBadge status="fail" label={`${failedCount} failed`} />
          {(runningCount > 0 || pendingCount > 0) && (
            <StatusBadge status="info" label={`${runningCount + pendingCount} remaining`} />
          )}
          {allFinalized && failedCount === 0 && warningCount === 0 && (
            <StatusBadge status="pass" label="All checks passed" />
          )}
          {allFinalized && (failedCount > 0 || warningCount > 0) && (
            <StatusBadge status="warning" label="Review issues before provisioning" />
          )}
        </div>

        <table>
          <thead>
            <tr>
              <th className="w-36">Status</th>
              <th className="w-56">Category</th>
              <th>Check</th>
              <th>Details</th>
              <th className="w-72">Quick Fix</th>
            </tr>
          </thead>
          <tbody>
            {checks.map((item) => (
              <tr key={item.name}>
                <td>
                  <StatusBadge status={toBadgeStatus(item.status)} label={item.status} />
                </td>
                <td className="text-sm text-gray-600">{item.category || 'System'}</td>
                <td className="font-medium">{item.name}</td>
                <td className="text-sm text-gray-600">{item.message || 'No details.'}</td>
                <td className="text-sm text-gray-600">
                  {item.quickFix && ['Failed', 'Warning'].includes(item.status) ? (
                    <div className="flex items-center gap-2">
                      {item.canRemediate && (
                        <button
                          type="button"
                          onClick={() => handleInstall(item.name)}
                          disabled={Boolean(installingCheck)}
                          className="px-2 py-1 bg-[#007ACC] text-white rounded text-xs font-medium hover:bg-[#005A9C] disabled:opacity-50 transition-colors"
                        >
                          {installingCheck === item.name ? 'Installing...' : 'Install'}
                        </button>
                      )}
                      {item.quickFix.command && (
                        <button
                          type="button"
                          onClick={() => handleCopyCommand(item.name, item.quickFix.command)}
                          className="px-2 py-1 border border-gray-300 rounded text-xs font-medium hover:bg-gray-50 transition-colors"
                        >
                          {copiedCheck === item.name ? 'Copied' : 'Copy install cmd'}
                        </button>
                      )}
                      {item.quickFix.docsUrl && (
                        <a
                          href={item.quickFix.docsUrl}
                          target="_blank"
                          rel="noreferrer"
                          className="text-xs font-medium text-[#007ACC] hover:text-[#005A9C]"
                        >
                          Docs
                        </a>
                      )}
                    </div>
                  ) : (
                    <span className="text-xs text-gray-400">-</span>
                  )}
                </td>
              </tr>
            ))}
          </tbody>
        </table>
      </div>

      {error && (
        <div className="bg-red-50 border border-red-200 rounded-lg p-4 mb-6">
          <p className="text-red-800 font-medium">Check failed</p>
          <p className="text-red-600 text-sm mt-1">{error}</p>
        </div>
      )}
      {actionError && (
        <div className="bg-red-50 border border-red-200 rounded-lg p-4 mb-6">
          <p className="text-red-800 font-medium">Remediation failed</p>
          <p className="text-red-600 text-sm mt-1">{actionError}</p>
        </div>
      )}
      {actionMessage && (
        <div className="bg-green-50 border border-green-200 rounded-lg p-4 mb-6">
          <p className="text-green-800 font-medium">Remediation completed</p>
          <p className="text-green-700 text-sm mt-1">{actionMessage}</p>
        </div>
      )}
    </div>
  );
}
