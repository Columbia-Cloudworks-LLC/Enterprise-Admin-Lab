# Enterprise Admin Lab — Web UI

Modern Node.js + React web application for managing Hyper-V and Active Directory lab configurations. Replaces the legacy PowerShell HttpListener and Windows Forms dashboard.

## Features

- **Lab Configuration**: CRUD operations for lab JSON configurations
- **Prerequisites Check**: Streaming system validation with color-coded results
- **Prerequisite Remediation**: One-click install/remediation actions for supported checks
- **Multi-tab Form**: Intuitive lab setup with 6 configuration sections
- **Real-time Validation**: Client-side and server-side validation
- **Responsive Design**: Works on desktop and tablet browsers

## Prerequisites

- **Node.js 20 LTS** or later, available at https://nodejs.org/
- Windows 10 Pro / Windows 11 / Windows Server 2016+ (for the lab provisioning itself)

## Installation

```powershell
cd Web
npm install
```

## Development

Start both the Express backend (port 47001) and Vite dev server (port 47173) in parallel:

```powershell
npm run dev
```

Open http://localhost:47173 in your browser.

**Vite dev server proxies all `/api/*` requests to the Express server.**

## Production Build

```powershell
npm run build
```

Outputs optimized React app to `dist/`. Then run:

```powershell
npm start
```

Express serves the built app on http://localhost:47000 alongside the API.

## Architecture

```
server/
  index.js                 # Express app entry point
  validation.js            # Lab config validation rules
  routes/
    labs.js               # CRUD: GET/POST/PUT/DELETE /api/labs
    defaults.js           # GET /api/defaults
    schema.js             # GET /api/schema
    templates.js          # GET /api/templates, /api/templates/:name
    prerequisites.js      # GET /api/prerequisites* + POST /api/prerequisites/remediate

client/
  src/
    main.jsx              # React entry point
    App.jsx               # Layout and routing
    components/
      LabList.jsx         # Labs table
      LabConfigForm/
        index.jsx         # Smart form container
        GeneralTab.jsx
        DomainTab.jsx
        NetworksTab.jsx
        BaseImagesTab.jsx
        VMDefinitionsTab.jsx
        StorageTab.jsx
      PrerequisitesPanel.jsx
      StatusBadge.jsx
    hooks/
      useLabs.js          # Lab CRUD API calls
      usePrerequisites.js # Prerequisites check/remediation API calls
    validation.js         # Client-side validation rules
    styles/
      index.css           # Tailwind + custom CSS
```

## API Endpoints

All responses are JSON. Validation errors follow the format:

```json
{
  "isValid": false,
  "errors": [
    {"field": "metadata.name", "message": "Lab name is invalid..."}
  ]
}
```

Client-side routes in the React app are different from API routes:

- `/labs/new` -- open the New Lab form
- `/labs/:name/edit` -- open the Edit Lab form
- `/api/labs/:name` -- read/update lab config data (server endpoint)

| Method | Path | Response |
|--------|------|----------|
| GET | `/api/labs` | `[{name, displayName, vmCount, lastModified}]` |
| GET | `/api/labs/:name` | full lab config |
| POST | `/api/labs` | `{success, errors[]}` |
| PUT | `/api/labs/:name` | `{success, errors[]}` |
| DELETE | `/api/labs/:name` | `{success}` |
| GET | `/api/defaults` | global defaults.json |
| GET | `/api/schema` | lab-schema.json |
| GET | `/api/templates` | `[{name, displayName}]` |
| GET | `/api/templates/:name` | template config |
| GET | `/api/prerequisites/checks` | static prerequisite check metadata |
| GET | `/api/prerequisites/stream` | SSE stream for live prerequisite check updates |
| GET | `/api/prerequisites` | merged prerequisite results |
| POST | `/api/prerequisites/remediate` | `{ok, name, message}` or `{error, details}` |

## Validation Rules

Same rules as the PowerShell `Test-EALabConfig` module:

- Lab name slug: `^[a-z0-9][a-z0-9-]{1,48}[a-z0-9]$`
- Required domain fields (`fqdn`, `netbiosName`)
- At least one network with unique names and valid CIDR
- At least one VM with DomainController role
- `secureBoot` only on Gen 2 VMs
- `tpmEnabled` only on Gen 2 + windowsClient
- Hardware ranges: CPU 1–16, RAM 512–65536 MB, disk 20–2000 GB

## Integration with PowerShell Entry Point

The main `Invoke-EALab.ps1` script launches this web app:

```powershell
# Default action — start web UI
.\Invoke-EALab.ps1

# Explicit switch
.\Invoke-EALab.ps1 -OpenWebUI

# Pure PowerShell validation (no Node.js needed)
.\Invoke-EALab.ps1 -Validate

# Run remediation for a specific prerequisite
.\Invoke-EALab.ps1 -RemediatePrerequisite -PrerequisiteName "Oscdimg Tool"

# List labs
.\Invoke-EALab.ps1 -List
```

## Styling

The app uses **Tailwind CSS** for utility-based styling with a project-specific colour scheme:

- Primary blue: `#007ACC` (header, links, buttons)
- Sidebar dark: `#2D2D30` (nav background)
- Content white: `#F0F0F0`
- Status colours: green (passed), yellow (warning), red (failed)

## Browser Support

- Chrome/Edge 90+
- Firefox 88+
- Safari 14+

(Older browsers may work but are not officially supported.)

## Troubleshooting

**Port 47001 or 47173 already in use?**

Kill the existing process or modify the port in `server/index.js` (Express) or `client/vite.config.js` (Vite).

**npm install fails?**

- Ensure you're npm v10+ (ships with Node 20 LTS)
- Delete `package-lock.json` and `node_modules/`, then retry
- Check your internet connection

**Express server won't start?**

- Check that `Labs/` and `Config/` directories exist in the parent directory
- Verify file permissions
- Check the terminal for detailed error messages

**Install button fails for remediation?**

- Ensure the current session is elevated ("Run as Administrator")
- Re-run `.\Invoke-EALab.ps1 -Validate` to confirm current state
- For `Oscdimg Tool`, install Windows ADK Deployment Tools first, then retry remediation

## License

Part of the Enterprise Admin Lab project. See the root repository for licensing details.
