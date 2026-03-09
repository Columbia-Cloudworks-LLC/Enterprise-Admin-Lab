import { FormField, FormSelect, getFieldErrors } from './FormUtils.jsx';

export default function GeneralTab({ config, onChange, errors, isEditMode }) {
  const metadata = config.metadata || {};
  const tabErrors = getFieldErrors(errors, 'metadata');

  const handleAddTag = (e) => {
    if (e.key === 'Enter') {
      e.preventDefault();
      const input = e.currentTarget;
      const tag = input.value.trim();
      if (tag && !metadata.tags?.includes(tag)) {
        onChange('metadata.tags', [...(metadata.tags || []), tag]);
        input.value = '';
      }
    }
  };

  const handleRemoveTag = (tag) => {
    onChange('metadata.tags', metadata.tags.filter((t) => t !== tag));
  };

  return (
    <div>
      <h3 className='text-lg font-bold mb-4'>General Information</h3>

      <FormField
        label='Lab Name (slug)'
        field='metadata.name'
        value={metadata.name}
        onChange={onChange}
        errors={tabErrors}
        placeholder='e.g., my-lab-01'
        disabled={isEditMode}
        pattern='^[a-z0-9][a-z0-9-]{1,48}[a-z0-9]$'
      />

      <FormField
        label='Display Name'
        field='metadata.displayName'
        value={metadata.displayName}
        onChange={onChange}
        errors={tabErrors}
        placeholder='e.g., My Test Lab'
      />

      <div className='mb-4'>
        <label className='block mb-1 font-medium text-gray-700'>Description</label>
        <textarea
          value={metadata.description || ''}
          onChange={(e) => onChange('metadata.description', e.target.value)}
          rows={3}
          placeholder='Optional description of this lab'
          className='w-full'
        />
      </div>

      <FormField
        label='Author'
        field='metadata.author'
        value={metadata.author}
        onChange={onChange}
        errors={tabErrors}
        placeholder='Your name'
      />

      <div className='mb-4'>
        <label className='block mb-1 font-medium text-gray-700'>Tags</label>
        <input
          type='text'
          placeholder='Type a tag and press Enter'
          onKeyDown={handleAddTag}
          className='w-full'
        />
        <div className='mt-2 flex flex-wrap gap-2'>
          {(metadata.tags || []).map((tag) => (
            <div
              key={tag}
              className='inline-flex items-center gap-2 bg-blue-100 text-blue-800 px-3 py-1 rounded-full'
            >
              <span className='text-sm'>{tag}</span>
              <button
                type='button'
                onClick={() => handleRemoveTag(tag)}
                className='text-blue-600 hover:text-blue-900 font-bold'
              >
                ×
              </button>
            </div>
          ))}
        </div>
      </div>
    </div>
  );
}
