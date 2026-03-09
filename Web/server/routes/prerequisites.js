import express from 'express';
import { spawn, execSync } from 'child_process';
import path from 'path';
import { fileURLToPath } from 'url';

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);

const router = express.Router();
const scriptPath = path.resolve(__dirname, '../../../Invoke-EALab.ps1');
const isDebugWebEnabled = /^(1|true|yes)$/i.test(String(process.env.EALAB_DEBUG_WEB || ''));

const MAX_OUTPUT_BYTES = 1 * 1024 * 1024; // 1 MB output cap guards against runaway processes
const TIMEOUT_MS = 30_000;                // 30 s kill timer

const PREREQUISITE_CHECKS = [
  { name: 'Administrator Elevation', category: 'System', message: 'Checks if the session is elevated.' },
  { name: 'PowerShell Version', category: 'System', message: 'Checks minimum supported PowerShell version.' },
  { name: 'Windows Edition', category: 'System', message: 'Checks Windows edition supports Hyper-V.' },
  { name: 'Hyper-V Feature', category: 'Hyper-V', message: 'Checks Hyper-V Windows feature state.' },
  { name: 'Hyper-V Management Tools', category: 'Hyper-V', message: 'Checks Hyper-V management tools state.' },
  { name: 'Hyper-V PowerShell Module', category: 'Hyper-V', message: 'Checks Hyper-V module availability.' },
  { name: 'ImportExcel Module', category: 'Modules', message: 'Checks ImportExcel module availability.' },
  { name: 'Disk Space', category: 'Storage', message: 'Checks available storage against minimum guidance.' },
  { name: 'Default vSwitch', category: 'Network', message: 'Checks Hyper-V virtual switch availability.' },
  {
    name: 'Terraform CLI',
    category: 'Provisioning',
    message: 'Checks Terraform CLI availability.',
    canRemediate: true,
    quickFix: {
      docsUrl: 'https://developer.hashicorp.com/terraform/downloads',
      command: 'winget install --id Hashicorp.Terraform --exact --accept-source-agreements --accept-package-agreements',
    },
  },
  {
    name: 'Docker Desktop',
    category: 'Provisioning',
    message: 'Checks Docker Desktop/daemon availability.',
    canRemediate: true,
    quickFix: {
      docsUrl: 'https://www.docker.com/products/docker-desktop',
      command: 'winget install --id Docker.DockerDesktop --exact --accept-source-agreements --accept-package-agreements',
    },
  },
  {
    name: 'Oscdimg Tool',
    category: 'Provisioning',
    message: 'Checks oscdimg.exe availability for unattended media generation.',
    canRemediate: true,
    quickFix: {
      docsUrl: 'https://learn.microsoft.com/windows-hardware/get-started/adk-install',
      command: '.\\Invoke-EALab.ps1 -RemediatePrerequisite -PrerequisiteName "Oscdimg Tool"',
    },
  },
];

// Prefer PowerShell 7 (pwsh); fall back to Windows PowerShell 5.1.
// Resolved once at startup so every request pays no extra cost.
let psExe = 'powershell.exe';
try {
  execSync('pwsh.exe -NoProfile -Command exit 0', { stdio: 'ignore', timeout: 5_000 });
  psExe = 'pwsh.exe';
} catch { /* pwsh not available – stay with powershell.exe */ }

function stripAnsi(value) {
  return value.replace(/\u001b\[[0-9;]*m/g, '');
}

function normalizeParsedStatus(statusTag) {
  const statusMap = {
    OK: 'Passed',
    FAIL: 'Failed',
    WARN: 'Warning',
  };
  return statusMap[statusTag] || 'Warning';
}

function parsePrerequisiteLine(line) {
  const normalizedLine = stripAnsi(line).replace(/\r/g, '').trimEnd();
  const statusMatch = normalizedLine.match(/^\s*\[(OK|FAIL|WARN|\?\?)\]\s+(.*)$/);
  if (!statusMatch) {
    return null;
  }

  const statusTag = statusMatch[1].toUpperCase();
  const remainder = statusMatch[2].trim();

  // Prefer deterministic parsing using the known check catalog instead of
  // relying on variable column spacing in console output.
  for (const check of PREREQUISITE_CHECKS) {
    if (!remainder.startsWith(check.name)) {
      continue;
    }

    const afterName = remainder.slice(check.name.length).trimStart();
    if (!afterName.startsWith(check.category)) {
      continue;
    }

    const message = afterName.slice(check.category.length).trimStart();
    return {
      name: check.name,
      category: check.category,
      status: normalizeParsedStatus(statusTag),
      message,
    };
  }

  // Fallback regex parser keeps compatibility with unexpected/legacy rows.
  const fallbackMatch = remainder.match(/^(.+?)\s{2,}([A-Za-z][A-Za-z0-9\- ]*)\s+(.*)$/);
  if (!fallbackMatch) {
    return null;
  }

  return {
    name: fallbackMatch[1].trim(),
    category: fallbackMatch[2].trim(),
    status: normalizeParsedStatus(statusTag),
    message: fallbackMatch[3].trim(),
  };
}

// Parse PowerShell tabular output into structured results
function parsePrerequisitesOutput(output) {
  const results = [];
  const lines = output.split('\n');
  for (const line of lines) {
    if (!line.trim()) {
      continue;
    }

    const parsedLine = parsePrerequisiteLine(line);
    if (parsedLine) {
      results.push(parsedLine);
    }
  }

  return results;
}

function buildMergedResults(parsedResults) {
  const byName = new Map(parsedResults.map((item) => [item.name, item]));
  return PREREQUISITE_CHECKS.map((check) => {
    const result = byName.get(check.name);
    if (result) {
      return {
        ...check,
        ...result,
      };
    }

    return {
      ...check,
      status: 'Warning',
      message: `No result returned for this check. ${check.message}`,
    };
  });
}

function sendSseEvent(res, event, payload) {
  res.write(`event: ${event}\n`);
  res.write(`data: ${JSON.stringify(payload)}\n\n`);
}

function debugLog(message, details = '') {
  if (!isDebugWebEnabled) {
    return;
  }
  const suffix = details ? ` ${details}` : '';
  console.log(`[EALab Debug] [prerequisites] ${message}${suffix}`);
}

function runPrerequisitesProcess({ onStdoutLine, onComplete, onFailure }) {
  const validateArgs = ['-NonInteractive', '-NoProfile', '-File', scriptPath, '-Validate'];
  if (isDebugWebEnabled) {
    validateArgs.push('-Debug');
  }
  debugLog('Spawning prerequisites process:', `${psExe} ${validateArgs.join(' ')}`);
  const ps = spawn(psExe, validateArgs);

  let stdout = '';
  let stderr = '';
  let outputBytes = 0;
  let timedOut = false;
  let stdoutBuffer = '';

  const timer = setTimeout(() => {
    timedOut = true;
    ps.kill('SIGTERM');
    onFailure({ code: 504, error: `Prerequisites check timed out after ${TIMEOUT_MS / 1000} seconds.` });
  }, TIMEOUT_MS);

  ps.stdout.on('data', (data) => {
    outputBytes += data.length;
    if (outputBytes <= MAX_OUTPUT_BYTES) {
      const chunk = data.toString();
      stdout += chunk;
      stdoutBuffer += chunk;

      while (stdoutBuffer.includes('\n')) {
        const lineBreakIndex = stdoutBuffer.indexOf('\n');
        const line = stdoutBuffer.slice(0, lineBreakIndex);
        stdoutBuffer = stdoutBuffer.slice(lineBreakIndex + 1);
        onStdoutLine(line);
      }
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
    if (timedOut) {
      return;
    }
    debugLog('Prerequisites process exited.', `code=${code}`);
    if (isDebugWebEnabled && stdout.trim()) {
      console.log(`[EALab Debug] [prerequisites] Validate stdout:\n${stdout}`);
    }
    if (isDebugWebEnabled && stderr.trim()) {
      console.log(`[EALab Debug] [prerequisites] Validate stderr:\n${stderr}`);
    }

    if (stdoutBuffer.trim()) {
      onStdoutLine(stdoutBuffer);
    }

    onComplete({ code, stdout, stderr });
  });

  ps.on('error', (err) => {
    clearTimeout(timer);
    onFailure({ code: 500, error: `Failed to execute PowerShell: ${err.message}` });
  });

  return ps;
}

router.get('/checks', (req, res) => {
  res.json(PREREQUISITE_CHECKS);
});

router.post('/remediate', (req, res) => {
  const prerequisiteName = typeof req.body?.name === 'string' ? req.body.name.trim() : '';
  if (!prerequisiteName) {
    return res.status(400).json({ error: 'Missing prerequisite name.' });
  }

  const knownCheck = PREREQUISITE_CHECKS.find((check) => check.name === prerequisiteName);
  if (!knownCheck) {
    return res.status(404).json({ error: `Unknown prerequisite '${prerequisiteName}'.` });
  }

  if (!knownCheck.canRemediate) {
    return res.status(400).json({ error: `No remediation available for '${prerequisiteName}'.` });
  }

  const remediationArgs = [
    '-NonInteractive',
    '-NoProfile',
    '-File',
    scriptPath,
    '-RemediatePrerequisite',
    '-PrerequisiteName',
    prerequisiteName,
  ];
  if (isDebugWebEnabled) {
    remediationArgs.push('-Debug');
  }
  debugLog('Spawning remediation process:', `${psExe} ${remediationArgs.join(' ')}`);
  const ps = spawn(psExe, remediationArgs);

  let stdout = '';
  let stderr = '';
  let outputBytes = 0;
  let timedOut = false;
  const remediationTimeoutMs = 10 * 60 * 1000;
  const timer = setTimeout(() => {
    timedOut = true;
    ps.kill('SIGTERM');
    return res.status(504).json({ error: `Remediation timed out after ${remediationTimeoutMs / 1000} seconds.` });
  }, remediationTimeoutMs);

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
    if (timedOut) {
      return;
    }
    debugLog('Remediation process exited.', `code=${code}`);
    if (isDebugWebEnabled && stdout.trim()) {
      console.log(`[EALab Debug] [prerequisites] Remediation stdout:\n${stdout}`);
    }
    if (isDebugWebEnabled && stderr.trim()) {
      console.log(`[EALab Debug] [prerequisites] Remediation stderr:\n${stderr}`);
    }

    if (code !== 0) {
      const details = stderr.trim() || stdout.trim() || `PowerShell exited with code ${code}.`;
      return res.status(500).json({ error: `Remediation failed for '${prerequisiteName}'.`, details });
    }

    return res.json({
      ok: true,
      name: prerequisiteName,
      message: `Remediation executed for '${prerequisiteName}'.`,
      output: stdout.trim(),
    });
  });

  ps.on('error', (err) => {
    clearTimeout(timer);
    return res.status(500).json({ error: `Failed to start remediation: ${err.message}` });
  });
});

router.get('/stream', (req, res) => {
  res.setHeader('Content-Type', 'text/event-stream');
  res.setHeader('Cache-Control', 'no-cache, no-transform');
  res.setHeader('Connection', 'keep-alive');
  res.flushHeaders();

  const incrementalResults = [];
  sendSseEvent(res, 'start', { checks: PREREQUISITE_CHECKS });

  const ps = runPrerequisitesProcess({
    onStdoutLine: (line) => {
      const parsedLine = parsePrerequisiteLine(line);
      if (!parsedLine) {
        return;
      }

      const checkMeta = PREREQUISITE_CHECKS.find((check) => check.name === parsedLine.name);
      const enriched = checkMeta ? { ...checkMeta, ...parsedLine } : parsedLine;
      incrementalResults.push(enriched);
      sendSseEvent(res, 'update', enriched);
    },
    onComplete: ({ code, stdout, stderr }) => {
      if (code !== 0 && stderr) {
        sendSseEvent(res, 'error', { error: stderr.trim() || 'An internal error occurred.' });
        return res.end();
      }

      const parsedResults = incrementalResults.length > 0 ? incrementalResults : parsePrerequisitesOutput(stdout);
      const mergedResults = buildMergedResults(parsedResults);
      sendSseEvent(res, 'complete', { results: mergedResults });
      return res.end();
    },
    onFailure: ({ error }) => {
      sendSseEvent(res, 'error', { error });
      return res.end();
    },
  });

  req.on('close', () => {
    if (ps && !ps.killed) {
      ps.kill('SIGTERM');
    }
  });
});

// GET /api/prerequisites - run PowerShell validation
router.get('/', (req, res) => {
  runPrerequisitesProcess({
    onStdoutLine: () => {},
    onComplete: ({ code, stdout, stderr }) => {
      if (code !== 0 && stderr) {
        console.error('[EALab] PowerShell prerequisites stderr:', stderr);
        return res.status(500).json({ error: 'An internal error occurred' });
      }

      const parsedResults = parsePrerequisitesOutput(stdout);
      const mergedResults = buildMergedResults(parsedResults);
      return res.json(mergedResults);
    },
    onFailure: ({ code, error }) => {
      return res.status(code || 500).json({ error });
    },
  });
});

export default router;
