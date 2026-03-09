import { useState, useEffect } from 'react';
import { useNavigate, useParams } from 'react-router-dom';
import { saveLab } from '../../hooks/useLabs.js';
import GeneralTab from './GeneralTab.jsx';
import DomainTab from './DomainTab.jsx';
import NetworksTab from './NetworksTab.jsx';
import BaseImagesTab from './BaseImagesTab.jsx';
import VMDefinitionsTab from './VMDefinitionsTab.jsx';
import StorageTab from './StorageTab.jsx';
import { validateLabConfig } from '../../validation.js';

const TABS = [
  { id: 'general', label: 'General Info' },
  { id: 'domain', label: 'Domain Settings' },
  { id: 'networks', label: 'Networks' },
  { id: 'baseImages', label: 'Base Images' },
  { id: 'vmDefinitions', label: 'VM Definitions' },
  { id: 'storage', label: 'Storage Paths' },
];

export default function LabConfigForm({ mode }) {
  const navigate = useNavigate();
  const { name: routeLabName } = useParams();
  const [config, setConfig] = useState(null);
  const [activeTab, setActiveTab] = useState('general');
  const [errors, setErrors] = useState([]);
  const [tabErrors, setTabErrors] = useState({});
  const [toast, setToast] = useState(null);
  const [isSaving, setIsSaving] = useState(false);
  const [loadError, setLoadError] = useState('');

  // Initialize config based on mode
  useEffect(() => {
    const initConfig = async () => {
      try {
        let newConfig;
        setLoadError('');

        if (mode === 'new') {
          // Load template
          const resp = await fetch('/api/templates/basic-ad-lab');
          if (!resp.ok) {
            throw new Error(`Failed to load new lab template (${resp.status})`);
          }
          newConfig = await resp.json();
          // Clear identifiers
          if (newConfig.metadata) {
            newConfig.metadata.name = '';
            newConfig.metadata.displayName = '';
            newConfig.metadata.created = null;
            newConfig.metadata.modified = null;
          }
        } else {
          // mode === 'edit' - resolve from route params
          if (!routeLabName) {
            setLoadError('Invalid edit URL. Please open a lab from the list and try again.');
            return;
          }

          const resp = await fetch(`/api/labs/${encodeURIComponent(routeLabName)}`);
          if (!resp.ok) {
            throw new Error(`Lab "${routeLabName}" was not found (${resp.status})`);
          }
          newConfig = await resp.json();
        }

        setConfig(newConfig);
      } catch (err) {
        setLoadError(err.message);
        showToast(`Error loading config: ${err.message}`, 'error');
      }
    };

    initConfig();
  }, [mode, routeLabName]);

  const showToast = (message, type = 'success') => {
    setToast({ message, type });
    setTimeout(() => setToast(null), 3000);
  };

  const handleChange = (field, value) => {
    setConfig((prev) => {
      const updated = JSON.parse(JSON.stringify(prev));
      const parts = field.split('.');
      let obj = updated;
      for (let i = 0; i < parts.length - 1; i++) {
        obj = obj[parts[i]];
      }
      obj[parts[parts.length - 1]] = value;
      return updated;
    });
  };

  const handleTabChange = (newTab) => {
    setActiveTab(newTab);
  };

  const handleSubmit = async () => {
    // Validate
    const validation = validateLabConfig(config);
    if (!validation.isValid) {
      setErrors(validation.errors);
      
      // Compute which tabs have errors
      const tabErrMap = {};
      validation.errors.forEach((err) => {
        const section = err.field.split('.')[0];
        const tabId = section === 'metadata' ? 'general' : section;
        tabErrMap[tabId] = true;
      });
      setTabErrors(tabErrMap);
      
      showToast('Please fix validation errors before saving', 'error');
      return;
    }

    // Save
    setIsSaving(true);
    try {
      if (mode === 'edit' && !routeLabName) {
        showToast('Cannot save: missing lab identifier in URL', 'error');
        return;
      }

      const labName = config.metadata.name;
      const result = await saveLab(config, {
        isNew: mode === 'new',
        originalName: mode === 'edit' ? routeLabName : labName,
      });
      if (result.success) {
        showToast('Lab saved successfully!', 'success');
        setTimeout(() => navigate('/'), 1500);
      } else {
        setErrors(result.errors || []);
        showToast('Server validation failed', 'error');
      }
    } catch (err) {
      showToast(`Error: ${err.message}`, 'error');
    } finally {
      setIsSaving(false);
    }
  };

  if (loadError) {
    return (
      <div className='bg-red-50 border border-red-200 rounded p-4 text-red-800'>
        {loadError}
      </div>
    );
  }

  if (!config) {
    return <div className='text-center text-gray-500'>Loading...</div>;
  }

  return (
    <div className='flex flex-col gap-4 max-w-4xl'>
      {/* Header */}
      <div className='flex justify-between items-center'>
        <h2 className='text-2xl font-bold text-gray-900'>
          {mode === 'new' ? 'New Lab Configuration' : `Edit: ${config.metadata?.displayName}`}
        </h2>
      </div>

      {/* Tabs */}
      <div className='tab-list'>
        {TABS.map((tab) => (
          <button
            key={tab.id}
            onClick={() => handleTabChange(tab.id)}
            className={`tab ${activeTab === tab.id ? 'active' : ''} ${tabErrors[tab.id] ? 'has-error' : ''}`}
          >
            {tab.label}
          </button>
        ))}
      </div>

      {/* Tab Content */}
      <div className='bg-white rounded shadow p-6'>
        {activeTab === 'general' && (
          <GeneralTab
            config={config}
            onChange={handleChange}
            errors={errors}
            isEditMode={mode === 'edit'}
          />
        )}
        {activeTab === 'domain' && (
          <DomainTab config={config} onChange={handleChange} errors={errors} />
        )}
        {activeTab === 'networks' && (
          <NetworksTab config={config} onChange={handleChange} errors={errors} />
        )}
        {activeTab === 'baseImages' && (
          <BaseImagesTab config={config} onChange={handleChange} errors={errors} />
        )}
        {activeTab === 'vmDefinitions' && (
          <VMDefinitionsTab config={config} onChange={handleChange} errors={errors} />
        )}
        {activeTab === 'storage' && (
          <StorageTab config={config} onChange={handleChange} errors={errors} />
        )}
      </div>

      {/* Error Summary */}
      {errors.length > 0 && (
        <div className='bg-red-50 border border-red-200 rounded p-4'>
          <h3 className='font-bold text-red-800 mb-2'>Validation Errors:</h3>
          <ul className='list-disc list-inside text-red-700 text-sm space-y-1'>
            {errors.map((err, i) => (
              <li key={i}>
                <strong>{err.field}:</strong> {err.message}
              </li>
            ))}
          </ul>
        </div>
      )}

      {/* Buttons */}
      <div className='flex gap-2 justify-end'>
        <button
          onClick={() => navigate('/')}
          className='px-4 py-2 bg-gray-300 text-gray-900 rounded hover:bg-gray-400 font-medium'
          disabled={isSaving}
        >
          Cancel
        </button>
        <button
          onClick={handleSubmit}
          disabled={isSaving}
          className='px-4 py-2 bg-[#007ACC] text-white rounded hover:bg-blue-700 disabled:bg-gray-400 font-medium'
        >
          {isSaving ? 'Saving...' : 'Save'}
        </button>
      </div>

      {/* Toast */}
      {toast && (
        <div className={`toast ${toast.type === 'error' ? 'toast-error' : 'toast-success'}`}>
          {toast.message}
        </div>
      )}
    </div>
  );
}
