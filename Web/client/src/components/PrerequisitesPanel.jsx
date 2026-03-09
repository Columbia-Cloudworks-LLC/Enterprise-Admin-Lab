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
  const { checks, loading, error, runCheck } = usePrerequisites();
  const failedCount = checks.filter((item) => item.status === 'Failed').length;
  const warningCount = checks.filter((item) => item.status === 'Warning').length;
  const passedCount = checks.filter((item) => item.status === 'Passed').length;
  const runningCount = checks.filter((item) => item.status === 'Running').length;
  const pendingCount = checks.filter((item) => item.status === 'Pending').length;
  const totalChecks = checks.length;
  const allFinalized = totalChecks > 0 && checks.every((item) => ['Passed', 'Failed', 'Warning'].includes(item.status));

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
    </div>
  );
}
