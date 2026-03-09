import { FormField, FormSelect, getFieldErrors } from './FormUtils.jsx';

const DOMAIN_LEVELS = ['Win2012R2', 'Win2016', 'Win2019'];

export default function DomainTab({ config, onChange, errors }) {
  const domain = config.domain || {};
  const tabErrors = getFieldErrors(errors, 'domain');

  return (
    <div>
      <h3 className='text-lg font-bold mb-4'>Active Directory Domain Settings</h3>

      <FormField
        label='Domain FQDN'
        field='domain.fqdn'
        value={domain.fqdn}
        onChange={onChange}
        errors={tabErrors}
        placeholder='e.g., contoso.com'
      />

      <FormField
        label='NetBIOS Name'
        field='domain.netbiosName'
        value={domain.netbiosName}
        onChange={onChange}
        errors={tabErrors}
        placeholder='e.g., CONTOSO'
      />

      <FormSelect
        label='Functional Level'
        field='domain.functionalLevel'
        value={domain.functionalLevel}
        onChange={onChange}
        options={DOMAIN_LEVELS}
        errors={tabErrors}
      />

      <div className='mb-4'>
        <label className='block mb-1 font-medium text-gray-700'>Safe Mode Password</label>
        <input
          type='password'
          value={domain.safeModePassword || ''}
          onChange={(e) => onChange('domain.safeModePassword', e.target.value)}
          placeholder='DSRM password (optional)'
          className='w-full'
        />
        <p className='text-xs text-gray-500 mt-1'>Leave blank to generate during provisioning</p>
      </div>
    </div>
  );
}
