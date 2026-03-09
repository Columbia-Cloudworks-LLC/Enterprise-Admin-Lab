import { FormField } from './FormUtils.jsx';

const OS_TYPES = [
  { key: 'windowsServer2019', label: 'Windows Server 2019', fields: ['isoPath', 'productKey'] },
  { key: 'windowsServer2022', label: 'Windows Server 2022', fields: ['isoPath', 'productKey'] },
  { key: 'windowsClient', label: 'Windows Client', fields: ['isoPath', 'productKey'] },
  { key: 'linux', label: 'Linux', fields: ['isoPath', 'distro'] },
];

export default function BaseImagesTab({ config, onChange, errors }) {
  const baseImages = config.baseImages || {};

  const handleFieldChange = (osKey, field, value) => {
    const updated = { ...baseImages };
    if (!updated[osKey]) {
      updated[osKey] = {};
    }
    updated[osKey] = { ...updated[osKey], [field]: value };
    onChange('baseImages', updated);
  };

  return (
    <div>
      <h3 className='text-lg font-bold mb-4'>Base Images</h3>
      <p className='text-sm text-gray-500 mb-6'>
        Configure ISO paths and product keys for each operating system used in your lab VMs.
      </p>

      {OS_TYPES.map((os) => {
        const imageConfig = baseImages[os.key] || {};
        return (
          <div key={os.key} className='border rounded p-4 mb-4 bg-gray-50'>
            <h4 className='font-bold text-gray-700 mb-3'>{os.label}</h4>

            <div className='mb-4'>
              <label className='block mb-1 font-medium text-gray-700'>ISO Path</label>
              <input
                type='text'
                value={imageConfig.isoPath || ''}
                onChange={(e) => handleFieldChange(os.key, 'isoPath', e.target.value)}
                placeholder='e.g., C:\\ISOs\\Win2022.iso'
                className='w-full'
              />
            </div>

            {os.fields.includes('productKey') && (
              <div className='mb-4'>
                <label className='block mb-1 font-medium text-gray-700'>Product Key</label>
                <input
                  type='text'
                  value={imageConfig.productKey || ''}
                  onChange={(e) => handleFieldChange(os.key, 'productKey', e.target.value)}
                  placeholder='XXXXX-XXXXX-XXXXX-XXXXX-XXXXX'
                  className='w-full'
                />
              </div>
            )}

            {os.fields.includes('distro') && (
              <div className='mb-4'>
                <label className='block mb-1 font-medium text-gray-700'>Distribution</label>
                <input
                  type='text'
                  value={imageConfig.distro || ''}
                  onChange={(e) => handleFieldChange(os.key, 'distro', e.target.value)}
                  placeholder='e.g., Ubuntu 22.04'
                  className='w-full'
                />
              </div>
            )}
          </div>
        );
      })}
    </div>
  );
}
