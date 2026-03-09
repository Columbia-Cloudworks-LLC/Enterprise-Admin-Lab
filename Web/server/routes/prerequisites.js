import express from 'express';
import { spawn, execSync } from 'child_process';
import path from 'path';
import { fileURLToPath } from 'url';

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);

const router = express.Router();
const scriptPath = path.resolve(__dirname, '../../../Invoke-EALab.ps1');

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
  { name: 'Terraform CLI', category: 'Provisioning', message: 'Checks Terraform CLI availability.' },
  { name: 'Docker Desktop', category: 'Provisioning', message: 'Checks Docker Desktop/daemon availability.' },
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
  const match = normalizedLine.match(/^\s*\[(OK|FAIL|WARN|\?\?)\]\s+(.+?)\s{2,}([A-Za-z][A-Za-z0-9\- ]*)\s{2,}(.*)$/);
  if (!match) {
    return null;
  }

  return {
    name: match[2].trim(),
    category: match[3].trim(),
    status: normalizeParsedStatus(match[1].toUpperCase()),
    message: match[4].trim(),
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
      return result;
    }

    return {
      name: check.name,
      category: check.category,
      status: 'Warning',
      message: 'No result returned for this check.',
    };
  });
}

function sendSseEvent(res, event, payload) {
  res.write(`event: ${event}\n`);
  res.write(`data: ${JSON.stringify(payload)}\n\n`);
}

function runPrerequisitesProcess({ onStdoutLine, onComplete, onFailure }) {
  const ps = spawn(psExe, ['-NonInteractive', '-NoProfile', '-File', scriptPath, '-Validate']);

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

      incrementalResults.push(parsedLine);
      sendSseEvent(res, 'update', parsedLine);
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
