import { Routes, Route, NavLink as RouterNavLink } from 'react-router-dom';
import LabList from './components/LabList.jsx';
import LabConfigForm from './components/LabConfigForm/index.jsx';
import PrerequisitesPanel from './components/PrerequisitesPanel.jsx';

export default function App() {
  return (
    <div className='flex flex-col h-screen bg-gray-100'>
      {/* Header */}
      <header className='bg-[#007ACC] text-white px-6 py-5 shadow-md'>
        <h1 className='text-2xl font-bold'>Enterprise Admin Lab v3.0.0</h1>
      </header>

      {/* Main Content */}
      <div className='flex flex-1 overflow-hidden'>
        {/* Sidebar Navigation */}
        <nav className='w-48 bg-[#2D2D30] text-white overflow-y-auto'>
          <SidebarLink to='/' label='Labs' end />
          <SidebarLink to='/prerequisites' label='Prerequisites' />
        </nav>

        {/* Content Area */}
        <main className='flex-1 overflow-y-auto p-6'>
          <Routes>
            <Route path='/' element={<LabList />} />
            <Route path='/labs/new' element={<LabConfigForm mode='new' />} />
            <Route path='/labs/:name/edit' element={<LabConfigForm mode='edit' />} />
            <Route path='/prerequisites' element={<PrerequisitesPanel />} />
            <Route path='*' element={<NotFoundPanel />} />
          </Routes>
        </main>
      </div>
    </div>
  );
}

function SidebarLink({ to, label, end = false }) {
  return (
    <RouterNavLink
      to={to}
      end={end}
      className={({ isActive }) =>
        `block w-full px-4 py-3 text-left text-sm font-medium transition-colors ${
          isActive
            ? 'bg-[#007ACC] text-white'
            : 'text-gray-300 hover:bg-[#3E3E42] hover:text-white'
        }`
      }
    >
      {label}
    </RouterNavLink>
  );
}

function NotFoundPanel() {
  return (
    <div className='bg-yellow-50 border border-yellow-200 rounded p-4 text-yellow-900'>
      <h2 className='font-bold mb-1'>Page not found</h2>
      <p>The requested route does not exist. Use the left navigation to return to a valid page.</p>
    </div>
  );
}
