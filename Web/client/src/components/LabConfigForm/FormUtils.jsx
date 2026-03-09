function getFieldErrors(errors, fieldPrefix) {
  return errors.filter((e) => e.field.startsWith(fieldPrefix));
}

function fieldError(errors, field) {
  const err = errors.find((e) => e.field === field);
  return err ? err.message : null;
}

export function FormField({ label, field, value, onChange, errors = [], type = 'text', disabled = false, ...props }) {
  const error = fieldError(errors, field);
  return (
    <div className='mb-4'>
      <label className='block mb-1 font-medium text-gray-700'>{label}</label>
      <input
        type={type}
        value={value || ''}
        onChange={(e) => onChange(field, e.target.value)}
        disabled={disabled}
        className={error ? 'error-field' : ''}
        {...props}
      />
      {error && <div className='error-message'>{error}</div>}
    </div>
  );
}

export function FormSelect({ label, field, value, onChange, options, errors = [], ...props }) {
  const error = fieldError(errors, field);
  return (
    <div className='mb-4'>
      <label className='block mb-1 font-medium text-gray-700'>{label}</label>
      <select
        value={value || ''}
        onChange={(e) => onChange(field, e.target.value)}
        className={error ? 'error-field' : ''}
        {...props}
      >
        <option value=''>-- Select --</option>
        {options.map((opt) => (
          <option key={opt} value={opt}>
            {opt}
          </option>
        ))}
      </select>
      {error && <div className='error-message'>{error}</div>}
    </div>
  );
}

export { getFieldErrors };
