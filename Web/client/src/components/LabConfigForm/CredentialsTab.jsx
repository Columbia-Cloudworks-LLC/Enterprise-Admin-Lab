import { useMemo, useState } from 'react';
import { FormField, getFieldErrors } from './FormUtils.jsx';
import { setCredentialRef, testCredentialRefs } from '../../hooks/useLabs.js';

function collectCredentialRefs(config) {
  const refs = new Set();
  const credentials = config?.credentials || {};
  ['localAdminRef', 'domainAdminRef', 'dsrmRef'].forEach((fieldName) => {
    const value = String(credentials[fieldName] || '').trim();
    if (value) refs.add(value);
  });

  const vmDefinitions = Array.isArray(config?.vmDefinitions) ? config.vmDefinitions : [];
  vmDefinitions.forEach((vmDef) => {
    const join = vmDef?.guestConfiguration?.domainJoin;
    if (join?.enabled === true) {
      const value = String(join.credentialRef || '').trim();
      if (value) refs.add(value);
    }
  });

  return Array.from(refs.values());
}

export default function CredentialsTab({ config, onChange, errors }) {
  const tabErrors = getFieldErrors(errors, 'credentials');
  const [checking, setChecking] = useState(false);
  const [saving, setSaving] = useState(false);
  const [statusRows, setStatusRows] = useState([]);
  const [statusMessage, setStatusMessage] = useState('');
  const [modalRef, setModalRef] = useState('');
  const [modalUserName, setModalUserName] = useState('');
  const [modalPassword, setModalPassword] = useState('');

  const credentials = config.credentials || {};
  const refs = useMemo(() => collectCredentialRefs(config), [config]);

  const openSetModal = (ref) => {
    setModalRef(ref);
    setModalUserName('');
    setModalPassword('');
  };

  const closeSetModal = () => {
    setModalRef('');
    setModalUserName('');
    setModalPassword('');
  };

  const handleValidateRefs = async () => {
    if (refs.length === 0) {
      setStatusRows([]);
      setStatusMessage('No credential refs configured.');
      return;
    }

    setChecking(true);
    setStatusMessage('');
    try {
      const result = await testCredentialRefs(refs);
      const rows = Array.isArray(result.results) ? result.results : [];
      setStatusRows(rows);
      const missing = rows.filter((row) => !row.Exists);
      if (missing.length > 0) {
        setStatusMessage(`Missing refs: ${missing.map((row) => row.Ref).join(', ')}`);
      } else {
        setStatusMessage('All configured refs resolved successfully.');
      }
    } catch (err) {
      setStatusMessage(`Credential check failed: ${err.message}`);
    } finally {
      setChecking(false);
    }
  };

  const handleSaveCredential = async () => {
    if (!modalRef) return;
    if (!modalUserName.trim() || !modalPassword) {
      setStatusMessage('Username and password are required to set a credential.');
      return;
    }

    setSaving(true);
    setStatusMessage('');
    try {
      await setCredentialRef({
        target: modalRef,
        username: modalUserName.trim(),
        password: modalPassword,
      });
      closeSetModal();
      setStatusMessage(`Credential '${modalRef}' saved.`);
      await handleValidateRefs();
    } catch (err) {
      setStatusMessage(`Failed to save '${modalRef}': ${err.message}`);
    } finally {
      setSaving(false);
    }
  };

  return (
    <div>
      <h3 className='text-lg font-bold mb-4'>Credential Configuration</h3>
      <p className='text-sm text-gray-600 mb-4'>
        For ephemeral labs, you can store inline credentials directly in config files for single-click launches, or keep using Windows Credential Manager refs.
      </p>

      <FormField
        label='Local Admin Credential Ref'
        field='credentials.localAdminRef'
        value={credentials.localAdminRef}
        onChange={onChange}
        errors={tabErrors}
        placeholder='e.g., ealab-local-admin'
      />
      <FormField
        label='Local Admin Username (inline)'
        field='credentials.localAdminUser'
        value={credentials.localAdminUser}
        onChange={onChange}
        errors={tabErrors}
        placeholder='e.g., Administrator'
      />
      <FormField
        label='Local Admin Password (inline)'
        field='credentials.localAdminPassword'
        value={credentials.localAdminPassword}
        onChange={onChange}
        errors={tabErrors}
        type='password'
        placeholder='Inline lab password'
      />

      <FormField
        label='Domain Admin Credential Ref'
        field='credentials.domainAdminRef'
        value={credentials.domainAdminRef}
        onChange={onChange}
        errors={tabErrors}
        placeholder='e.g., ealab-domain-admin'
      />
      <FormField
        label='Domain Admin Username (inline)'
        field='credentials.domainAdminUser'
        value={credentials.domainAdminUser}
        onChange={onChange}
        errors={tabErrors}
        placeholder='e.g., LAB\\Administrator'
      />
      <FormField
        label='Domain Admin Password (inline)'
        field='credentials.domainAdminPassword'
        value={credentials.domainAdminPassword}
        onChange={onChange}
        errors={tabErrors}
        type='password'
        placeholder='Inline lab password'
      />

      <FormField
        label='DSRM Credential Ref'
        field='credentials.dsrmRef'
        value={credentials.dsrmRef}
        onChange={onChange}
        errors={tabErrors}
        placeholder='e.g., ealab-dsrm'
      />
      <FormField
        label='DSRM Username (inline, optional)'
        field='credentials.dsrmUser'
        value={credentials.dsrmUser}
        onChange={onChange}
        errors={tabErrors}
        placeholder='Default: DSRM'
      />
      <FormField
        label='DSRM Password (inline)'
        field='credentials.dsrmPassword'
        value={credentials.dsrmPassword}
        onChange={onChange}
        errors={tabErrors}
        type='password'
        placeholder='Inline DSRM password'
      />

      <div className='flex gap-2 mb-3'>
        <button
          type='button'
          onClick={handleValidateRefs}
          disabled={checking}
          className='px-3 py-2 bg-sky-600 text-white rounded hover:bg-sky-700 disabled:bg-gray-400 text-sm font-medium'
        >
          {checking ? 'Checking...' : 'Validate Credentials'}
        </button>
      </div>

      {statusMessage && (
        <div className='mb-3 text-sm text-gray-700'>{statusMessage}</div>
      )}

      {statusRows.length > 0 && (
        <div className='border rounded p-3 text-sm'>
          <div className='font-semibold mb-2'>Credential status</div>
          <ul className='space-y-2'>
            {statusRows.map((row) => (
              <li key={row.Ref} className='flex items-center justify-between gap-3'>
                <div>
                  <div><span className='font-mono'>{row.Ref}</span> - {row.Exists ? 'Found' : 'Missing'}</div>
                  <div className='text-xs text-gray-500'>Provider: {row.Provider || '-'}</div>
                </div>
                <button
                  type='button'
                  onClick={() => openSetModal(row.Ref)}
                  className='px-2 py-1 bg-[#007ACC] text-white rounded hover:bg-blue-700 text-xs font-medium'
                >
                  Set / Update
                </button>
              </li>
            ))}
          </ul>
        </div>
      )}

      {modalRef && (
        <div className='fixed inset-0 z-50 bg-black/50 flex items-center justify-center'>
          <div className='bg-white rounded shadow p-5 w-full max-w-md'>
            <h4 className='text-lg font-bold mb-3'>Set Credential Ref</h4>
            <p className='text-sm text-gray-600 mb-4'>Target: <span className='font-mono'>{modalRef}</span></p>
            <div className='mb-3'>
              <label className='block mb-1 font-medium text-gray-700'>Username</label>
              <input
                type='text'
                value={modalUserName}
                onChange={(event) => setModalUserName(event.target.value)}
                placeholder='DOMAIN\\User or .\\Administrator'
              />
            </div>
            <div className='mb-4'>
              <label className='block mb-1 font-medium text-gray-700'>Password</label>
              <input
                type='password'
                value={modalPassword}
                onChange={(event) => setModalPassword(event.target.value)}
                placeholder='Password'
                autoComplete='new-password'
              />
            </div>
            <div className='flex justify-end gap-2'>
              <button
                type='button'
                onClick={closeSetModal}
                className='px-3 py-2 bg-gray-300 text-gray-900 rounded hover:bg-gray-400 text-sm font-medium'
              >
                Cancel
              </button>
              <button
                type='button'
                onClick={handleSaveCredential}
                disabled={saving}
                className='px-3 py-2 bg-[#007ACC] text-white rounded hover:bg-blue-700 disabled:bg-gray-400 text-sm font-medium'
              >
                {saving ? 'Saving...' : 'Save Credential'}
              </button>
            </div>
          </div>
        </div>
      )}
    </div>
  );
}
