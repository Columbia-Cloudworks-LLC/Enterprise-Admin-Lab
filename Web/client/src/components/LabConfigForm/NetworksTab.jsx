import { FormField, FormSelect, getFieldErrors } from './FormUtils.jsx';

const SWITCH_TYPES = ['Internal', 'Private', 'External'];

export default function NetworksTab({ config, onChange, errors }) {
  const networks = config.networks || [];
  const tabErrors = getFieldErrors(errors, 'networks');

  const handleAddNetwork = () => {
    const newNetwork = {
      name: '',
      switchType: 'Internal',
      subnet: '',
      gateway: '',
      dnsServers: [],
    };
    onChange('networks', [...networks, newNetwork]);
  };

  const handleRemoveNetwork = (idx) => {
    onChange('networks', networks.filter((_, i) => i !== idx));
  };

  const handleNetworkFieldChange = (idx, field, value) => {
    const updated = [...networks];
    const parts = field.split('.');
    let obj = updated[idx];
    for (let i = 1; i < parts.length - 1; i++) {
      obj = obj[parts[i]];
    }
    obj[parts[parts.length - 1]] = value;
    onChange('networks', updated);
  };

  return (
    <div>
      <h3 className='text-lg font-bold mb-4'>Virtual Networks</h3>

      {networks.length === 0 && (
        <p className='text-gray-500 mb-4'>No networks defined. Click "Add Network" to create one.</p>
      )}

      {networks.map((net, idx) => {
        const prefix = `networks[${idx}]`;
        const netErrors = tabErrors.filter((e) => e.field.startsWith(prefix));

        return (
          <div key={idx} className='border rounded p-4 mb-4 bg-gray-50'>
            <div className='flex justify-between items-center mb-3'>
              <h4 className='font-bold text-gray-700'>Network {idx + 1}</h4>
              <button
                type='button'
                onClick={() => handleRemoveNetwork(idx)}
                className='text-red-600 hover:text-red-900 font-bold'
              >
                Remove
              </button>
            </div>

            <FormField
              label='Network Name'
              field={`${prefix}.name`}
              value={net.name}
              onChange={(f, v) => handleNetworkFieldChange(idx, f.split('.').slice(1).join('.'), v)}
              errors={netErrors}
              placeholder='e.g., LabInternal'
            />

            <FormSelect
              label='Switch Type'
              field={`${prefix}.switchType`}
              value={net.switchType}
              onChange={(f, v) => handleNetworkFieldChange(idx, f.split('.').slice(1).join('.'), v)}
              options={SWITCH_TYPES}
              errors={netErrors}
            />

            <FormField
              label='Subnet (CIDR)'
              field={`${prefix}.subnet`}
              value={net.subnet}
              onChange={(f, v) => handleNetworkFieldChange(idx, f.split('.').slice(1).join('.'), v)}
              errors={netErrors}
              placeholder='e.g., 192.168.10.0/24'
            />

            <FormField
              label='Gateway (optional)'
              field={`${prefix}.gateway`}
              value={net.gateway}
              onChange={(f, v) => handleNetworkFieldChange(idx, f.split('.').slice(1).join('.'), v)}
              errors={netErrors}
              placeholder='e.g., 192.168.10.1'
            />

            <div className='mb-4'>
              <label className='block mb-1 font-medium text-gray-700'>DNS Servers (comma-separated, optional)</label>
              <input
                type='text'
                value={(net.dnsServers || []).join(', ')}
                onChange={(e) => {
                  const dns = e.target.value
                    .split(',')
                    .map((s) => s.trim())
                    .filter((s) => s);
                  handleNetworkFieldChange(idx, 'dnsServers', dns);
                }}
                placeholder='e.g., 8.8.8.8, 8.8.4.4'
                className='w-full'
              />
            </div>
          </div>
        );
      })}

      <button
        type='button'
        onClick={handleAddNetwork}
        className='px-4 py-2 bg-green-600 text-white rounded hover:bg-green-700 font-medium'
      >
        Add Network
      </button>
    </div>
  );
}
