import { useState } from 'react';
import { useNavigate } from 'react-router-dom';
import {
  useLabs,
  deleteLab,
  launchLab,
  destroyLabEnvironment,
  fetchLabStatus,
} from '../hooks/useLabs.js';
import StatusBadge from './StatusBadge.jsx';

function statusToVariant(status) {
  switch (status) {
    case 'Running':
      return 'pass';
    case 'Creating':
    case 'Destroying':
      return 'info';
    case 'Error':
      return 'fail';
    case 'Destroyed':
      return 'neutral';
    default:
      return 'warning';
  }
}

export default function LabList() {
  const navigate = useNavigate();
  const { labs, loading, error, refetch } = useLabs();
  const [selectedLab, setSelectedLab] = useState(null);
  const [busyAction, setBusyAction] = useState(false);

  const handleNew = () => {
    navigate('/labs/new');
  };

  const handleEdit = () => {
    if (selectedLab) {
      navigate(`/labs/${encodeURIComponent(selectedLab.name)}/edit`);
    }
  };

  const handleDelete = async () => {
    if (!selectedLab || !window.confirm(`Delete lab "${selectedLab.displayName}"?`)) {
      return;
    }

    try {
      const result = await deleteLab(selectedLab.name);
      if (result.success) {
        setSelectedLab(null);
        await refetch();
      } else {
        alert('Failed to delete lab');
      }
    } catch (err) {
      alert(`Error: ${err.message}`);
    }
  };

  const handleLaunch = async (skipOrchestration = false) => {
    if (!selectedLab) return;
    setBusyAction(true);
    try {
      const result = await launchLab(selectedLab.name, { skipOrchestration });
      if (!result.success) {
        alert(result.error || 'Failed to launch lab');
      }
      await refetch();
    } catch (err) {
      alert(`Launch failed: ${err.message}`);
    } finally {
      setBusyAction(false);
    }
  };

  const handleDestroyEnvironment = async () => {
    if (!selectedLab) return;
    if (!window.confirm(`Destroy VM resources for "${selectedLab.displayName}"?`)) {
      return;
    }

    setBusyAction(true);
    try {
      const result = await destroyLabEnvironment(selectedLab.name);
      if (!result.success) {
        alert(result.error || 'Failed to destroy lab resources');
      }
      await refetch();
    } catch (err) {
      alert(`Destroy failed: ${err.message}`);
    } finally {
      setBusyAction(false);
    }
  };

  const handleRefreshStatus = async () => {
    if (!selectedLab) return;
    setBusyAction(true);
    try {
      await fetchLabStatus(selectedLab.name);
      await refetch();
    } catch (err) {
      alert(`Status refresh failed: ${err.message}`);
    } finally {
      setBusyAction(false);
    }
  };

  const selectedStatus = selectedLab?.status || 'NotCreated';
  const isLifecycleBusy = ['Creating', 'Destroying'].includes(selectedStatus);
  const selectedStep = selectedLab?.statusStep || '';
  const selectedMessage = selectedLab?.statusMessage || '';
  const selectedOperationLog = selectedLab?.operationLog || '';
  const selectedAnsibleLog = selectedLab?.statusDetails?.ansibleLog || '';
  const selectedVmProgress = Array.isArray(selectedLab?.vmProgressSummary) ? selectedLab.vmProgressSummary : [];

  return (
    <div className='flex flex-col gap-4'>
      {/* Header */}
      <div className='flex justify-between items-center'>
        <h2 className='text-2xl font-bold text-gray-900'>Lab Configurations</h2>
        <div className='flex gap-2'>
          <button
            onClick={handleNew}
            className='px-4 py-2 bg-[#007ACC] text-white rounded hover:bg-blue-700 font-medium'
          >
            New Lab
          </button>
          <button
            onClick={handleEdit}
            disabled={!selectedLab || busyAction || isLifecycleBusy}
            className='px-4 py-2 bg-orange-500 text-white rounded hover:bg-orange-600 disabled:bg-gray-400 font-medium'
          >
            Edit
          </button>
          <button
            onClick={() => handleLaunch(false)}
            disabled={!selectedLab || busyAction || isLifecycleBusy}
            className='px-4 py-2 bg-green-600 text-white rounded hover:bg-green-700 disabled:bg-gray-400 font-medium'
          >
            Launch
          </button>
          <button
            onClick={() => handleLaunch(true)}
            disabled={!selectedLab || busyAction || isLifecycleBusy}
            className='px-4 py-2 bg-teal-600 text-white rounded hover:bg-teal-700 disabled:bg-gray-400 font-medium'
          >
            Launch (Hyper-V only)
          </button>
          <button
            onClick={handleDestroyEnvironment}
            disabled={!selectedLab || busyAction || isLifecycleBusy}
            className='px-4 py-2 bg-purple-600 text-white rounded hover:bg-purple-700 disabled:bg-gray-400 font-medium'
          >
            Destroy VMs
          </button>
          <button
            onClick={handleRefreshStatus}
            disabled={!selectedLab || busyAction}
            className='px-4 py-2 bg-sky-600 text-white rounded hover:bg-sky-700 disabled:bg-gray-400 font-medium'
          >
            Refresh Status
          </button>
          <button
            onClick={handleDelete}
            disabled={!selectedLab || busyAction || isLifecycleBusy}
            className='px-4 py-2 bg-red-600 text-white rounded hover:bg-red-700 disabled:bg-gray-400 font-medium'
          >
            Delete
          </button>
        </div>
      </div>

      {/* Loading / Error */}
      {loading && <div className='text-center py-8 text-gray-500'>Loading labs...</div>}
      {error && <div className='bg-red-50 text-red-800 p-4 rounded'>{error}</div>}

      {/* Labs Table */}
      {!loading && labs.length > 0 && (
        <div className='bg-white rounded shadow overflow-x-auto'>
          <table>
            <thead>
              <tr>
                <th style={{ width: '30%' }}>Name</th>
                <th style={{ width: '24%' }}>Display Name</th>
                <th style={{ width: '10%' }}>VM Count</th>
                <th style={{ width: '13%' }}>Status</th>
                <th style={{ width: '23%' }}>Last Modified</th>
              </tr>
            </thead>
            <tbody>
              {labs.map((lab) => (
                <tr
                  key={lab.name}
                  onClick={() => setSelectedLab(lab)}
                  className={`cursor-pointer ${
                    selectedLab?.name === lab.name ? 'bg-blue-50' : 'hover:bg-gray-50'
                  }`}
                >
                  <td className='font-mono text-sm'>{lab.name}</td>
                  <td>{lab.displayName || '-'}</td>
                  <td className='text-center'>{lab.vmCount}</td>
                  <td>
                    <StatusBadge
                      status={statusToVariant(lab.status)}
                      label={lab.status || 'NotCreated'}
                    />
                  </td>
                  <td className='text-sm text-gray-600'>
                    {lab.lastModified
                      ? new Date(lab.lastModified).toLocaleString()
                      : '-'
                    }
                  </td>
                </tr>
              ))}
            </tbody>
          </table>

          {selectedLab && (
            <div className='border-t p-4 bg-gray-50 text-sm'>
              <div><strong>Current step:</strong> {selectedStep || '-'}</div>
              <div><strong>Status message:</strong> {selectedMessage || '-'}</div>
              <div><strong>Operation log:</strong> {selectedOperationLog || '-'}</div>
              <div><strong>Ansible log:</strong> {selectedAnsibleLog || '-'}</div>
              <div className='mt-2'>
                <strong>VM progress:</strong>
                {selectedVmProgress.length === 0 ? (
                  <span> -</span>
                ) : (
                  <ul className='mt-1 ml-5 list-disc'>
                    {selectedVmProgress.map((item) => (
                      <li key={item.name}>
                        <span className='font-mono'>{item.name}</span> - {item.phase || 'unknown'} ({item.status || 'n/a'})
                      </li>
                    ))}
                  </ul>
                )}
              </div>
            </div>
          )}
        </div>
      )}

      {/* Empty State */}
      {!loading && labs.length === 0 && (
        <div className='text-center py-12 bg-white rounded shadow'>
          <p className='text-gray-500 mb-4'>No lab configurations found.</p>
          <button
            onClick={handleNew}
            className='px-6 py-2 bg-[#007ACC] text-white rounded hover:bg-blue-700 font-medium'
          >
            Create the first lab
          </button>
        </div>
      )}
    </div>
  );
}
