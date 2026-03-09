import { FormField, FormSelect, getFieldErrors } from './FormUtils.jsx';

const VM_ROLES = ['DomainController', 'MemberServer', 'Client', 'Linux'];
const VM_OS = [
  { value: 'windowsServer2019', label: 'Windows Server 2019' },
  { value: 'windowsServer2022', label: 'Windows Server 2022' },
  { value: 'windowsServer2025', label: 'Windows Server 2025' },
  { value: 'windowsClient', label: 'Windows Client' },
  { value: 'linux', label: 'Linux' },
];
const GENERATIONS = [1, 2];

export default function VMDefinitionsTab({ config, onChange, errors }) {
  const vms = config.vmDefinitions || [];
  const networks = config.networks || [];
  const tabErrors = getFieldErrors(errors, 'vmDefinitions');

  const handleAddVM = () => {
    const newVM = {
      name: '',
      role: 'MemberServer',
      os: 'windowsServer2022',
      generation: 2,
      secureBoot: false,
      tpmEnabled: false,
      hardware: {
        cpuCount: config.globalHardwareDefaults?.cpuCount || 2,
        memoryMB: config.globalHardwareDefaults?.memoryMB || 2048,
        diskSizeGB: config.globalHardwareDefaults?.diskSizeGB || 60,
      },
      network: networks.length > 0 ? networks[0].name : '',
      staticIP: '',
      count: 1,
      notes: '',
    };
    onChange('vmDefinitions', [...vms, newVM]);
  };

  const handleRemoveVM = (idx) => {
    onChange(
      'vmDefinitions',
      vms.filter((_, i) => i !== idx)
    );
  };

  const handleVMChange = (idx, field, value) => {
    const updated = JSON.parse(JSON.stringify(vms));
    const parts = field.split('.');
    let obj = updated[idx];
    for (let i = 0; i < parts.length - 1; i++) {
      obj = obj[parts[i]];
    }
    obj[parts[parts.length - 1]] = value;
    onChange('vmDefinitions', updated);
  };

  const handleNumericChange = (idx, field, value) => {
    const num = value === '' ? '' : parseInt(value, 10);
    handleVMChange(idx, field, isNaN(num) ? '' : num);
  };

  return (
    <div>
      <h3 className='text-lg font-bold mb-4'>VM Definitions</h3>

      {/* Global error for vmDefinitions (e.g. "At least one DomainController") */}
      {tabErrors
        .filter((e) => e.field === 'vmDefinitions')
        .map((err, i) => (
          <div key={i} className='bg-red-50 border border-red-200 rounded p-3 mb-4 text-red-700 text-sm'>
            {err.message}
          </div>
        ))}

      {vms.length === 0 && (
        <p className='text-gray-500 mb-4'>No VMs defined. Click "Add VM" to create one.</p>
      )}

      {vms.map((vm, idx) => {
        const prefix = `vmDefinitions[${idx}]`;
        const vmErrors = tabErrors.filter((e) => e.field.startsWith(prefix));

        return (
          <div key={idx} className='border rounded p-4 mb-4 bg-gray-50'>
            <div className='flex justify-between items-center mb-3'>
              <h4 className='font-bold text-gray-700'>
                VM {idx + 1}: {vm.name || '(unnamed)'}
              </h4>
              <button
                type='button'
                onClick={() => handleRemoveVM(idx)}
                className='text-red-600 hover:text-red-900 font-bold'
              >
                Remove
              </button>
            </div>

            <div className='grid grid-cols-2 gap-4'>
              {/* Name */}
              <div className='mb-4'>
                <label className='block mb-1 font-medium text-gray-700'>Name</label>
                <input
                  type='text'
                  value={vm.name || ''}
                  onChange={(e) => handleVMChange(idx, 'name', e.target.value)}
                  placeholder='e.g., DC01'
                  className={vmErrors.some((e) => e.field === `${prefix}.name`) ? 'error-field' : ''}
                />
                {vmErrors
                  .filter((e) => e.field === `${prefix}.name`)
                  .map((e, i) => (
                    <div key={i} className='error-message'>{e.message}</div>
                  ))}
              </div>

              {/* Role */}
              <div className='mb-4'>
                <label className='block mb-1 font-medium text-gray-700'>Role</label>
                <select
                  value={vm.role || ''}
                  onChange={(e) => handleVMChange(idx, 'role', e.target.value)}
                  className={vmErrors.some((e) => e.field === `${prefix}.role`) ? 'error-field' : ''}
                >
                  <option value=''>-- Select --</option>
                  {VM_ROLES.map((r) => (
                    <option key={r} value={r}>{r}</option>
                  ))}
                </select>
                {vmErrors
                  .filter((e) => e.field === `${prefix}.role`)
                  .map((e, i) => (
                    <div key={i} className='error-message'>{e.message}</div>
                  ))}
              </div>

              {/* OS */}
              <div className='mb-4'>
                <label className='block mb-1 font-medium text-gray-700'>Operating System</label>
                <select
                  value={vm.os || ''}
                  onChange={(e) => handleVMChange(idx, 'os', e.target.value)}
                  className={vmErrors.some((e) => e.field === `${prefix}.os`) ? 'error-field' : ''}
                >
                  <option value=''>-- Select --</option>
                  {VM_OS.map((o) => (
                    <option key={o.value} value={o.value}>{o.label}</option>
                  ))}
                </select>
                {vmErrors
                  .filter((e) => e.field === `${prefix}.os`)
                  .map((e, i) => (
                    <div key={i} className='error-message'>{e.message}</div>
                  ))}
              </div>

              {/* Generation */}
              <div className='mb-4'>
                <label className='block mb-1 font-medium text-gray-700'>Generation</label>
                <select
                  value={vm.generation ?? ''}
                  onChange={(e) => handleVMChange(idx, 'generation', parseInt(e.target.value, 10))}
                  className={vmErrors.some((e) => e.field === `${prefix}.generation`) ? 'error-field' : ''}
                >
                  <option value=''>-- Select --</option>
                  {GENERATIONS.map((g) => (
                    <option key={g} value={g}>Generation {g}</option>
                  ))}
                </select>
                {vmErrors
                  .filter((e) => e.field === `${prefix}.generation`)
                  .map((e, i) => (
                    <div key={i} className='error-message'>{e.message}</div>
                  ))}
              </div>

              {/* Network */}
              <div className='mb-4'>
                <label className='block mb-1 font-medium text-gray-700'>Network</label>
                <select
                  value={vm.network || ''}
                  onChange={(e) => handleVMChange(idx, 'network', e.target.value)}
                  className={vmErrors.some((e) => e.field === `${prefix}.network`) ? 'error-field' : ''}
                >
                  <option value=''>-- Select --</option>
                  {networks.map((n) => (
                    <option key={n.name} value={n.name}>{n.name}</option>
                  ))}
                </select>
                {vmErrors
                  .filter((e) => e.field === `${prefix}.network`)
                  .map((e, i) => (
                    <div key={i} className='error-message'>{e.message}</div>
                  ))}
              </div>

              {/* Static IP */}
              <div className='mb-4'>
                <label className='block mb-1 font-medium text-gray-700'>Static IP (optional)</label>
                <input
                  type='text'
                  value={vm.staticIP || ''}
                  onChange={(e) => handleVMChange(idx, 'staticIP', e.target.value)}
                  placeholder='e.g., 192.168.10.10'
                  className={vmErrors.some((e) => e.field === `${prefix}.staticIP`) ? 'error-field' : ''}
                />
                {vmErrors
                  .filter((e) => e.field === `${prefix}.staticIP`)
                  .map((e, i) => (
                    <div key={i} className='error-message'>{e.message}</div>
                  ))}
              </div>
            </div>

            {/* Checkboxes row */}
            <div className='flex gap-6 mb-4'>
              <label className='flex items-center gap-2 text-sm'>
                <input
                  type='checkbox'
                  checked={vm.secureBoot || false}
                  onChange={(e) => handleVMChange(idx, 'secureBoot', e.target.checked)}
                  disabled={vm.generation !== 2}
                />
                Secure Boot (Gen 2 only)
              </label>
              <label className='flex items-center gap-2 text-sm'>
                <input
                  type='checkbox'
                  checked={vm.tpmEnabled || false}
                  onChange={(e) => handleVMChange(idx, 'tpmEnabled', e.target.checked)}
                  disabled={vm.generation !== 2 || vm.os !== 'windowsClient'}
                />
                TPM (Gen 2 + Windows Client only)
              </label>
              {vmErrors
                .filter((e) => e.field === `${prefix}.secureBoot` || e.field === `${prefix}.tpmEnabled`)
                .map((e, i) => (
                  <div key={i} className='error-message'>{e.message}</div>
                ))}
            </div>

            {/* Hardware */}
            <h5 className='font-semibold text-gray-600 mb-2'>Hardware</h5>
            <div className='grid grid-cols-3 gap-4 mb-4'>
              <div>
                <label className='block mb-1 font-medium text-gray-700'>CPU Count (1-16)</label>
                <input
                  type='number'
                  min={1}
                  max={16}
                  value={vm.hardware?.cpuCount ?? ''}
                  onChange={(e) => handleNumericChange(idx, 'hardware.cpuCount', e.target.value)}
                  className={vmErrors.some((e) => e.field === `${prefix}.hardware.cpuCount`) ? 'error-field' : ''}
                />
              </div>
              <div>
                <label className='block mb-1 font-medium text-gray-700'>Memory MB (512-65536)</label>
                <input
                  type='number'
                  min={512}
                  max={65536}
                  step={512}
                  value={vm.hardware?.memoryMB ?? ''}
                  onChange={(e) => handleNumericChange(idx, 'hardware.memoryMB', e.target.value)}
                  className={vmErrors.some((e) => e.field === `${prefix}.hardware.memoryMB`) ? 'error-field' : ''}
                />
              </div>
              <div>
                <label className='block mb-1 font-medium text-gray-700'>Disk GB (20-2000)</label>
                <input
                  type='number'
                  min={20}
                  max={2000}
                  value={vm.hardware?.diskSizeGB ?? ''}
                  onChange={(e) => handleNumericChange(idx, 'hardware.diskSizeGB', e.target.value)}
                  className={vmErrors.some((e) => e.field === `${prefix}.hardware.diskSizeGB`) ? 'error-field' : ''}
                />
              </div>
            </div>

            {/* Count and Notes */}
            <div className='grid grid-cols-2 gap-4'>
              <div className='mb-4'>
                <label className='block mb-1 font-medium text-gray-700'>Instance Count</label>
                <input
                  type='number'
                  min={1}
                  value={vm.count ?? 1}
                  onChange={(e) => handleNumericChange(idx, 'count', e.target.value)}
                />
              </div>
              <div className='mb-4'>
                <label className='block mb-1 font-medium text-gray-700'>Notes</label>
                <input
                  type='text'
                  value={vm.notes || ''}
                  onChange={(e) => handleVMChange(idx, 'notes', e.target.value)}
                  placeholder='Optional notes'
                />
              </div>
            </div>
          </div>
        );
      })}

      <button
        type='button'
        onClick={handleAddVM}
        className='px-4 py-2 bg-green-600 text-white rounded hover:bg-green-700 font-medium'
      >
        Add VM
      </button>
    </div>
  );
}
