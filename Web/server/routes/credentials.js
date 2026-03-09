import express from 'express';
import path from 'path';
import { fileURLToPath } from 'url';
import { spawn, execSync } from 'child_process';

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);
const router = express.Router();

const credentialsModulePath = path.resolve(__dirname, '../../../Modules/EALabCredentials/EALabCredentials.psd1');
const MAX_OUTPUT_BYTES = 1 * 1024 * 1024;
const TIMEOUT_MS = 30_000;
const SAFE_REF_REGEX = /^[a-zA-Z0-9._-]{3,128}$/;

let psExe = 'powershell.exe';
try {
  execSync('pwsh.exe -NoProfile -Command exit 0', { stdio: 'ignore', timeout: 5_000 });
  psExe = 'pwsh.exe';
} catch {
  // Keep Windows PowerShell fallback.
}

function toPsSingleQuoted(value) {
  return `'${String(value ?? '').replaceAll("'", "''")}'`;
}

function parseJsonSafe(raw) {
  try {
    return JSON.parse(raw);
  } catch {
    return null;
  }
}

function runPowerShellScript(script) {
  return new Promise((resolve, reject) => {
    const ps = spawn(psExe, ['-NonInteractive', '-NoProfile', '-Command', script]);
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

      if (code !== 0) {
        const message = (stderr || stdout || `PowerShell exited with code ${code}`).trim();
        reject(Object.assign(new Error(message), { status: 500 }));
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

function validateRef(ref) {
  return SAFE_REF_REGEX.test(String(ref ?? ''));
}

router.get('/status', async (req, res) => {
  try {
    const refs = String(req.query.refs || '')
      .split(',')
      .map((value) => value.trim())
      .filter(Boolean);

    if (refs.length === 0) {
      return res.status(400).json({ success: false, error: 'At least one credential ref is required.' });
    }

    const invalid = refs.filter((value) => !validateRef(value));
    if (invalid.length > 0) {
      return res.status(400).json({ success: false, error: `Invalid credential refs: ${invalid.join(', ')}` });
    }

    const refsPs = refs.map((value) => toPsSingleQuoted(value)).join(', ');
    const script = [
      `$modulePath = ${toPsSingleQuoted(credentialsModulePath)}`,
      'Import-Module -Name $modulePath -Force -ErrorAction Stop | Out-Null',
      `$refs = @(${refsPs})`,
      '$results = foreach ($ref in $refs) { Test-EALabCredentialRef -CredentialRef $ref }',
      '$results | ConvertTo-Json -Depth 5 -Compress',
    ].join('; ');

    const output = await runPowerShellScript(script);
    const parsed = parseJsonSafe(output.stdout);
    const results = Array.isArray(parsed) ? parsed : (parsed ? [parsed] : []);
    return res.json({ success: true, results });
  } catch (err) {
    const status = err.status || 500;
    if (status >= 500) {
      console.error('[EALab] GET /api/credentials/status error:', err);
    }
    return res.status(status).json({ success: false, error: err.message || 'An internal error occurred' });
  }
});

router.post('/', async (req, res) => {
  try {
    const target = String(req.body?.target || '').trim();
    const userName = String(req.body?.username || '').trim();
    const password = String(req.body?.password || '');
    const provider = String(req.body?.provider || 'Auto').trim();

    if (!validateRef(target)) {
      return res.status(400).json({ success: false, error: 'Invalid target credential ref.' });
    }
    if (!userName) {
      return res.status(400).json({ success: false, error: 'username is required.' });
    }
    if (!password) {
      return res.status(400).json({ success: false, error: 'password is required.' });
    }
    if (!['Auto', 'CredentialManager', 'CmdKey'].includes(provider)) {
      return res.status(400).json({ success: false, error: 'provider must be Auto, CredentialManager, or CmdKey.' });
    }

    const script = [
      `$modulePath = ${toPsSingleQuoted(credentialsModulePath)}`,
      'Import-Module -Name $modulePath -Force -ErrorAction Stop | Out-Null',
      `$secure = ConvertTo-SecureString -String ${toPsSingleQuoted(password)} -AsPlainText -Force`,
      `$result = Set-EALabCredentialRef -CredentialRef ${toPsSingleQuoted(target)} -UserName ${toPsSingleQuoted(userName)} -SecurePassword $secure -Provider ${toPsSingleQuoted(provider)}`,
      '$result | ConvertTo-Json -Depth 5 -Compress',
    ].join('; ');

    const output = await runPowerShellScript(script);
    const parsed = parseJsonSafe(output.stdout);
    return res.json({ success: true, result: parsed || {} });
  } catch (err) {
    const status = err.status || 500;
    if (status >= 500) {
      console.error('[EALab] POST /api/credentials error:', err);
    }
    return res.status(status).json({ success: false, error: err.message || 'An internal error occurred' });
  }
});

router.delete('/:ref', async (req, res) => {
  try {
    const target = String(req.params.ref || '').trim();
    if (!validateRef(target)) {
      return res.status(400).json({ success: false, error: 'Invalid target credential ref.' });
    }

    const script = [
      `$modulePath = ${toPsSingleQuoted(credentialsModulePath)}`,
      'Import-Module -Name $modulePath -Force -ErrorAction Stop | Out-Null',
      `$result = Remove-EALabCredentialRef -CredentialRef ${toPsSingleQuoted(target)}`,
      '$result | ConvertTo-Json -Depth 5 -Compress',
    ].join('; ');

    const output = await runPowerShellScript(script);
    const parsed = parseJsonSafe(output.stdout);
    return res.json({ success: true, result: parsed || {} });
  } catch (err) {
    const status = err.status || 500;
    if (status >= 500) {
      console.error('[EALab] DELETE /api/credentials/:ref error:', err);
    }
    return res.status(status).json({ success: false, error: err.message || 'An internal error occurred' });
  }
});

export default router;
