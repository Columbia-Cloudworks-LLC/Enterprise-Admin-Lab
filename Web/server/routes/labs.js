import express from 'express';
import path from 'path';
import { fileURLToPath } from 'url';
import fs from 'fs/promises';
import { spawn, spawnSync, execSync } from 'child_process';
import { validateLabConfig } from '../validation.js';

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);

const router = express.Router();
const labsDir = path.resolve(__dirname, '../../../Labs');
const invokeScriptPath = path.resolve(__dirname, '../../../Invoke-EALab.ps1');
const MAX_OUTPUT_BYTES = 1 * 1024 * 1024;
const TIMEOUT_MS = 45 * 60 * 1000;
const isDebugWebEnabled = /^(1|true|yes)$/i.test(String(process.env.EALAB_DEBUG_WEB || ''));

function debugLog(message, details = '') {
  if (!isDebugWebEnabled) {
    return;
  }
  const suffix = details ? ` ${details}` : '';
  console.log(`[EALab Debug] [labs] ${message}${suffix}`);
}

let psExe = 'powershell.exe';
try {
  execSync('pwsh.exe -NoProfile -Command exit 0', { stdio: 'ignore', timeout: 5_000 });
  psExe = 'pwsh.exe';
} catch {
  // Keep Windows PowerShell fallback.
}

/**
 * Sanitize a lab name to prevent path traversal.
 * Strips all directory components and rejects names that contain
 * characters outside [a-zA-Z0-9_\- ].
 * @param {string} name
 * @returns {string} safe basename
 * @throws if the name is invalid
 */
function sanitizeLabName(name) {
  const base = path.basename(String(name ?? ''));
  if (!base || !/^[a-zA-Z0-9_\- ]+$/.test(base)) {
    throw Object.assign(new Error('Invalid lab name'), { status: 400 });
  }
  // Double-check the resolved path stays inside labsDir
  const resolved = path.resolve(labsDir, `${base}.json`);
  if (!resolved.startsWith(labsDir + path.sep)) {
    throw Object.assign(new Error('Invalid lab name'), { status: 400 });
  }
  return base;
}

async function resolveLabFilePath(labName) {
  const safeName = sanitizeLabName(labName);
  const directPath = path.join(labsDir, `${safeName}.json`);

  try {
    await fs.access(directPath);
    return directPath;
  } catch {
    // Fall back to scanning files by metadata.name for legacy/imported labs.
  }

  let files = [];
  try {
    files = await fs.readdir(labsDir);
  } catch {
    return null;
  }

  for (const file of files) {
    if (!file.endsWith('.json')) continue;
    const filePath = path.join(labsDir, file);
    try {
      const content = await fs.readFile(filePath, 'utf8');
      const parsed = JSON.parse(content);
      const metadataName = parsed?.metadata?.name;
      if (typeof metadataName !== 'string' || !metadataName.trim()) {
        continue;
      }
      if (sanitizeLabName(metadataName) === safeName) {
        return filePath;
      }
    } catch {
      // Ignore invalid/unreadable files; continue searching.
    }
  }

  return null;
}

// Helper: read lab config from disk
async function getLabConfig(labName) {
  const filePath = await resolveLabFilePath(labName);
  if (!filePath) {
    return null;
  }
  try {
    const content = await fs.readFile(filePath, 'utf8');
    return JSON.parse(content);
  } catch {
    return null;
  }
}

function getLabLogsPath(config) {
  const fromStorage = config?.storage?.logsPath;
  if (typeof fromStorage === 'string' && fromStorage.trim()) {
    return fromStorage;
  }
  return 'E:\\EALabs\\Logs';
}

function getVmInstanceNames(vmDefinition) {
  const baseName = String(vmDefinition?.name || '').trim();
  if (!baseName) {
    return [];
  }

  const rawCount = Number(vmDefinition?.count);
  const count = Number.isInteger(rawCount) && rawCount > 0 ? rawCount : 1;
  if (count <= 1) {
    return [baseName];
  }

  const names = [];
  for (let index = 1; index <= count; index += 1) {
    names.push(`${baseName}-${String(index).padStart(2, '0')}`);
  }
  return names;
}

function getExpectedVmNames(config) {
  const vmDefinitions = Array.isArray(config?.vmDefinitions) ? config.vmDefinitions : [];
  return vmDefinitions.flatMap((vmDefinition) => getVmInstanceNames(vmDefinition));
}

function getLiveVmState(config) {
  const expectedVmNames = getExpectedVmNames(config);
  if (expectedVmNames.length === 0) {
    return {
      expectedCount: 0,
      existingCount: 0,
      runningCount: 0,
      existingNames: [],
      error: '',
    };
  }

  const escapedNames = expectedVmNames.map((name) => `'${name.replace(/'/g, "''")}'`).join(', ');
  const script = [
    '$ErrorActionPreference = "SilentlyContinue"',
    `$expected = @(${escapedNames})`,
    '$existing = @()',
    '$running = 0',
    'foreach ($name in $expected) {',
    '  $vm = Get-VM -Name $name -ErrorAction SilentlyContinue',
    '  if ($null -eq $vm) { continue }',
    '  $existing += [string]$vm.Name',
    '  if ([string]$vm.State -eq "Running") { $running++ }',
    '}',
    '[PSCustomObject]@{',
    '  expectedCount = $expected.Count',
    '  existingCount = $existing.Count',
    '  runningCount = $running',
    '  existingNames = @($existing)',
    '} | ConvertTo-Json -Compress',
  ].join('; ');

  try {
    const processResult = spawnSync(psExe, ['-NoProfile', '-NonInteractive', '-Command', script], {
      encoding: 'utf8',
      timeout: 10_000,
      windowsHide: true,
    });
    if (processResult.error) {
      throw processResult.error;
    }
    if (processResult.status !== 0) {
      throw new Error((processResult.stderr || processResult.stdout || '').trim() || `PowerShell exited with ${processResult.status}.`);
    }

    const parsed = JSON.parse(String(processResult.stdout || '').trim());
    return {
      expectedCount: Number(parsed?.expectedCount) || expectedVmNames.length,
      existingCount: Number(parsed?.existingCount) || 0,
      runningCount: Number(parsed?.runningCount) || 0,
      existingNames: Array.isArray(parsed?.existingNames) ? parsed.existingNames : [],
      error: '',
    };
  } catch (err) {
    debugLog('Live VM status probe failed.', err?.message || '');
    return {
      expectedCount: expectedVmNames.length,
      existingCount: 0,
      runningCount: 0,
      existingNames: [],
      error: err?.message || 'Unable to query Hyper-V VM status.',
    };
  }
}

function reconcileLifecycleStatus(state, liveState) {
  const stateStatus = typeof state?.status === 'string' && state.status.trim()
    ? state.status.trim()
    : '';

  const noVmResources = liveState.expectedCount > 0 && liveState.existingCount === 0;
  if (noVmResources) {
    if (stateStatus === 'Destroying') {
      return {
        status: 'Destroyed',
        message: state?.message || 'No VM resources found. Lab appears destroyed.',
        step: state?.step || 'Complete',
        updated: state?.updated || '',
      };
    }

    if (stateStatus === 'Creating' || stateStatus === 'Running' || stateStatus === 'Error') {
      return {
        status: 'NotCreated',
        message: 'No VM resources were found for this lab. Previous state was reset.',
        step: '',
        updated: state?.updated || '',
      };
    }
  }

  if (!stateStatus) {
    if (liveState.existingCount === 0) {
      return { status: 'NotCreated', message: '', step: '', updated: '' };
    }
    return {
      status: 'Running',
      message: '',
      step: '',
      updated: '',
    };
  }

  return {
    status: stateStatus,
    message: state?.message || '',
    step: state?.step || '',
    updated: state?.updated || '',
  };
}

async function getLabStatus(config) {
  const logsPath = getLabLogsPath(config);
  const stateFile = path.join(logsPath, `${config?.metadata?.name || 'unknown'}.state.json`);
  const liveState = getLiveVmState(config);

  try {
    const raw = await fs.readFile(stateFile, 'utf8');
    const state = JSON.parse(raw);
    const reconciled = reconcileLifecycleStatus(state, liveState);
    const details = state.details || {};
    const vmProgress = details.vmProgress || {};
    const vmProgressSummary = Object.keys(vmProgress).map((vmName) => ({
      name: vmName,
      phase: vmProgress[vmName]?.phase || '',
      status: vmProgress[vmName]?.status || '',
      message: vmProgress[vmName]?.message || '',
      updated: vmProgress[vmName]?.updated || '',
    }));
    return {
      status: reconciled.status,
      message: reconciled.message,
      step: reconciled.step,
      updated: reconciled.updated,
      operationLog: state.operationLog || '',
      details,
      vmProgressSummary,
      liveVmState: liveState,
    };
  } catch {
    const reconciled = reconcileLifecycleStatus(null, liveState);
    return {
      status: reconciled.status,
      message: reconciled.message,
      step: reconciled.step,
      updated: reconciled.updated,
      operationLog: '',
      details: {},
      vmProgressSummary: [],
      liveVmState: liveState,
    };
  }
}

function runPowerShell(args) {
  return new Promise((resolve, reject) => {
    const effectiveArgs = isDebugWebEnabled ? [...args, '-Debug'] : [...args];
    debugLog('Spawning PowerShell command:', `${psExe} ${effectiveArgs.join(' ')}`);
    const ps = spawn(psExe, ['-NonInteractive', '-NoProfile', ...effectiveArgs]);
    let stdout = '';
    let stderr = '';
    let outputBytes = 0;
    let timedOut = false;

    const timer = setTimeout(() => {
      timedOut = true;
      ps.kill('SIGTERM');
      reject(Object.assign(new Error(`Operation timed out after ${TIMEOUT_MS / 1000} seconds.`), { status: 504 }));
    }, TIMEOUT_MS);

    ps.stdout.on('data', (data) => {
      outputBytes += data.length;
      if (outputBytes <= MAX_OUTPUT_BYTES) {
        stdout += data.toString();
      }
    });

    ps.stderr.on('data', (data) => {
      outputBytes += data.length;
      if (outputBytes <= MAX_OUTPUT_BYTES) {
        stderr += data.toString();
      }
    });

    ps.on('close', (code) => {
      clearTimeout(timer);
      if (timedOut) return;
      debugLog('PowerShell process exited.', `code=${code}`);
      if (isDebugWebEnabled && stdout.trim()) {
        console.log(`[EALab Debug] [labs] PowerShell stdout:\n${stdout}`);
      }
      if (isDebugWebEnabled && stderr.trim()) {
        console.log(`[EALab Debug] [labs] PowerShell stderr:\n${stderr}`);
      }

      if (code !== 0) {
        const message = (stderr || stdout || `PowerShell exited with code ${code}`).trim();
        let status = 500;
        if (message.includes('requires an elevated')) {
          status = 403;
        } else if (message.includes('Provisioning prerequisites failed')) {
          status = 400;
        } else if (message.includes('Windows unattended media generation is required')) {
          status = 400;
        } else if (message.includes('Domain dependency gate failed')) {
          status = 424;
        } else if (message.includes('Domain readiness timed out')) {
          status = 504;
        } else if (message.includes('did not become reachable through PowerShell Direct')) {
          status = 504;
        } else if (message.includes('already exists. Re-run create with -Force')) {
          status = 409;
        } else if (message.includes('The file exists.')) {
          status = 409;
        }
        reject(Object.assign(new Error(message), { status }));
        return;
      }

      resolve({ stdout: stdout.trim(), stderr: stderr.trim() });
    });

    ps.on('error', (err) => {
      clearTimeout(timer);
      reject(Object.assign(new Error(`Failed to start PowerShell: ${err.message}`), { status: 500 }));
    });
  });
}

function toBooleanFlag(value) {
  if (typeof value === 'boolean') return value;
  if (typeof value === 'string') {
    const normalized = value.trim().toLowerCase();
    return normalized === 'true' || normalized === '1' || normalized === 'yes';
  }
  if (typeof value === 'number') {
    return value === 1;
  }
  return false;
}

function parseMissingCredentialRefs(message) {
  const marker = 'Missing or unreadable credential refs:';
  if (!message || !message.includes(marker)) {
    return [];
  }

  const markerIndex = message.indexOf(marker);
  const start = markerIndex + marker.length;
  const remainder = message.slice(start);
  const endIndex = remainder.indexOf('.');
  const refsSegment = (endIndex >= 0 ? remainder.slice(0, endIndex) : remainder).trim();
  if (!refsSegment) {
    return [];
  }

  return refsSegment.split(',').map((value) => value.trim()).filter(Boolean);
}

// Helper: write lab config to disk
async function saveLabConfig(labName, config) {
  const safeName = sanitizeLabName(labName);
  const filePath = path.join(labsDir, `${safeName}.json`);
  // Ensure Labs directory exists
  await fs.mkdir(labsDir, { recursive: true });
  // Add timestamp
  if (!config.metadata) config.metadata = {};
  config.metadata.modified = new Date().toISOString();
  if (!config.metadata.created) {
    config.metadata.created = new Date().toISOString();
  }
  await fs.writeFile(filePath, JSON.stringify(config, null, 2), 'utf8');
}

// GET /api/labs - list all labs
router.get('/', async (req, res) => {
  try {
    const files = await fs.readdir(labsDir);
    const labs = [];

    for (const file of files) {
      if (!file.endsWith('.json') || file.includes('templates')) continue;

      const config = await getLabConfig(file.replace('.json', ''));
      if (config && config.metadata) {
        const state = await getLabStatus(config);
        labs.push({
          name: config.metadata.name || file.replace('.json', ''),
          displayName: config.metadata.displayName || config.metadata.name || file,
          vmCount: (config.vmDefinitions || []).length,
          lastModified: config.metadata.modified || config.metadata.created || '',
          status: state.status,
          statusMessage: state.message,
          statusStep: state.step,
          statusUpdated: state.updated,
          operationLog: state.operationLog,
          statusDetails: state.details,
          vmProgressSummary: state.vmProgressSummary,
        });
      }
    }

    res.json(labs.sort((a, b) => a.name.localeCompare(b.name)));
  } catch (err) {
    console.error('[EALab] GET /api/labs error:', err);
    res.status(500).json({ error: 'An internal error occurred' });
  }
});

// POST /api/labs/:name/launch - run provisioning
router.post('/:name/launch', async (req, res) => {
  try {
    const safeName = sanitizeLabName(req.params.name);
    const config = await getLabConfig(safeName);
    if (!config) {
      return res.status(404).json({ success: false, error: 'Lab not found' });
    }

    const args = ['-File', invokeScriptPath, '-Create', '-LabName', safeName, '-Force'];
    if (toBooleanFlag(req.body?.skipOrchestration)) {
      args.push('-SkipOrchestration');
    }
    const result = await runPowerShell(args);
    res.json({ success: true, output: result.stdout });
  } catch (err) {
    const status = err.status || 500;
    const errorMessage = err.message || 'An internal error occurred';
    const missingCredentialRefs = parseMissingCredentialRefs(errorMessage);
    if (status >= 500) {
      console.error('[EALab] POST /api/labs/:name/launch error:', err);
    }
    res.status(status).json({
      success: false,
      error: errorMessage,
      missingCredentialRefs,
    });
  }
});

// POST /api/labs/:name/destroy - remove lab resources
router.post('/:name/destroy', async (req, res) => {
  try {
    const safeName = sanitizeLabName(req.params.name);
    const config = await getLabConfig(safeName);
    if (!config) {
      return res.status(404).json({ success: false, error: 'Lab not found' });
    }

    const args = ['-File', invokeScriptPath, '-Destroy', '-LabName', safeName];
    if (toBooleanFlag(req.body?.deleteLabData)) {
      args.push('-DeleteLabData');
    }

    const result = await runPowerShell(args);
    res.json({ success: true, output: result.stdout });
  } catch (err) {
    const status = err.status || 500;
    if (status >= 500) {
      console.error('[EALab] POST /api/labs/:name/destroy error:', err);
    }
    res.status(status).json({ success: false, error: err.message || 'An internal error occurred' });
  }
});

// GET /api/labs/:name/status - read lifecycle state
router.get('/:name/status', async (req, res) => {
  try {
    const safeName = sanitizeLabName(req.params.name);
    const config = await getLabConfig(safeName);
    if (!config) {
      return res.status(404).json({ success: false, error: 'Lab not found' });
    }

    const state = await getLabStatus(config);
    res.json({
      success: true,
      name: safeName,
      status: state.status,
      message: state.message,
      step: state.step,
      updated: state.updated,
      operationLog: state.operationLog,
      details: state.details,
      vmProgressSummary: state.vmProgressSummary,
    });
  } catch (err) {
    const status = err.status || 500;
    if (status >= 500) {
      console.error('[EALab] GET /api/labs/:name/status error:', err);
    }
    res.status(status).json({ success: false, error: status < 500 ? err.message : 'An internal error occurred' });
  }
});

// GET /api/labs/:name - get single lab config
router.get('/:name', async (req, res) => {
  try {
    const config = await getLabConfig(req.params.name);
    if (!config) {
      return res.status(404).json({ error: 'Lab not found' });
    }
    res.json(config);
  } catch (err) {
    const status = err.status || 500;
    if (status >= 500) console.error('[EALab] GET /api/labs/:name error:', err);
    res.status(status).json({ error: status < 500 ? err.message : 'An internal error occurred' });
  }
});

// POST /api/labs - create new lab
router.post('/', async (req, res) => {
  try {
    const config = req.body;

    // Validate
    const validation = validateLabConfig(config);
    if (!validation.isValid) {
      return res.status(400).json({ success: false, errors: validation.errors });
    }

    // Sanitize the name from the body before saving
    const labName = sanitizeLabName(config.metadata.name);
    await saveLabConfig(labName, config);

    res.json({ success: true, errors: [] });
  } catch (err) {
    const status = err.status || 500;
    if (status >= 500) console.error('[EALab] POST /api/labs error:', err);
    res.status(status).json({ success: false, errors: [{ field: 'metadata.name', message: status < 500 ? err.message : 'An internal error occurred' }] });
  }
});

// PUT /api/labs/:name - update existing lab
router.put('/:name', async (req, res) => {
  try {
    const config = req.body;
    // Sanitize both the URL param and the name embedded in the body
    const existingLabName = sanitizeLabName(req.params.name);
    const newLabName = sanitizeLabName(config.metadata?.name);

    // Validate
    const validation = validateLabConfig(config);
    if (!validation.isValid) {
      return res.status(400).json({ success: false, errors: validation.errors });
    }

    // Check if Lab exists
    const existing = await getLabConfig(existingLabName);
    if (!existing) {
      return res.status(404).json({ success: false, errors: [{ field: '', message: 'Lab not found' }] });
    }
    const existingFilePath = await resolveLabFilePath(existingLabName);

    // Save first, then remove the old file if the name changed
    await saveLabConfig(newLabName, config);

    if (newLabName !== existingLabName && existingFilePath) {
      try {
        await fs.unlink(existingFilePath);
      } catch {
        // Ignore if file doesn't exist
      }
    }

    res.json({ success: true, errors: [] });
  } catch (err) {
    const status = err.status || 500;
    if (status >= 500) console.error('[EALab] PUT /api/labs/:name error:', err);
    res.status(status).json({ success: false, errors: [{ field: '', message: status < 500 ? err.message : 'An internal error occurred' }] });
  }
});

// DELETE /api/labs/:name - delete lab
router.delete('/:name', async (req, res) => {
  try {
    const safeName = sanitizeLabName(req.params.name);
    const filePath = await resolveLabFilePath(safeName);
    if (!filePath) {
      return res.status(404).json({ success: false });
    }
    await fs.unlink(filePath);
    res.json({ success: true });
  } catch (err) {
    const status = err.status || 500;
    if (status >= 500) console.error('[EALab] DELETE /api/labs/:name error:', err);
    res.status(status).json({ success: false, error: status < 500 ? err.message : 'An internal error occurred' });
  }
});

export default router;
