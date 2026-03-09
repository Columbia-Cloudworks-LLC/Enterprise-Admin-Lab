export default function StorageTab({ config, onChange, errors }) {
  const storage = config.storage || {};

  const handleChange = (field, value) => {
    onChange('storage', { ...storage, [field]: value });
  };

  return (
    <div>
      <h3 className='text-lg font-bold mb-4'>Storage Paths</h3>
      <p className='text-sm text-gray-500 mb-6'>
        Configure the root paths where Hyper-V VMs and logs will be stored during provisioning.
      </p>

      <div className='mb-4'>
        <label className='block mb-1 font-medium text-gray-700'>VM Root Path</label>
        <input
          type='text'
          value={storage.vmRootPath || ''}
          onChange={(e) => handleChange('vmRootPath', e.target.value)}
          placeholder='e.g., E:\EALabs'
          className='w-full'
        />
        <p className='text-xs text-gray-500 mt-1'>
          Root directory for Hyper-V virtual machine files and VHDs.
        </p>
      </div>

      <div className='mb-4'>
        <label className='block mb-1 font-medium text-gray-700'>Logs Path (optional)</label>
        <input
          type='text'
          value={storage.logsPath || ''}
          onChange={(e) => handleChange('logsPath', e.target.value)}
          placeholder='e.g., E:\EALabs\Logs'
          className='w-full'
        />
        <p className='text-xs text-gray-500 mt-1'>
          Directory for provisioning and operational logs.
        </p>
      </div>
    </div>
  );
}
