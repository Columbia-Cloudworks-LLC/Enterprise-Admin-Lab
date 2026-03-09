import express from 'express';
import path from 'path';
import { fileURLToPath } from 'url';
import fs from 'fs/promises';

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);

const router = express.Router();
const templatesDir = path.resolve(__dirname, '../../../Labs/templates');

/**
 * Sanitize a template name to prevent path traversal.
 * @param {string} name
 * @returns {string} safe basename
 * @throws if the name is invalid
 */
function sanitizeTemplateName(name) {
  const base = path.basename(String(name ?? ''));
  if (!base || !/^[a-zA-Z0-9_\- ]+$/.test(base)) {
    throw Object.assign(new Error('Invalid template name'), { status: 400 });
  }
  const resolved = path.resolve(templatesDir, `${base}.json`);
  if (!resolved.startsWith(templatesDir + path.sep)) {
    throw Object.assign(new Error('Invalid template name'), { status: 400 });
  }
  return base;
}

// GET /api/templates - list all templates
router.get('/', async (req, res) => {
  try {
    const files = await fs.readdir(templatesDir);
    const templates = [];

    for (const file of files) {
      if (!file.endsWith('.json')) continue;

      const filePath = path.join(templatesDir, file);
      const content = await fs.readFile(filePath, 'utf8');
      const config = JSON.parse(content);

      templates.push({
        name: config.metadata?.name || file.replace('.json', ''),
        displayName: config.metadata?.displayName || config.metadata?.name || file,
      });
    }

    res.json(templates.sort((a, b) => a.name.localeCompare(b.name)));
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
});

// GET /api/templates/:name - get single template
router.get('/:name', async (req, res) => {
  try {
    const safeName = sanitizeTemplateName(req.params.name);
    const filePath = path.join(templatesDir, `${safeName}.json`);
    const content = await fs.readFile(filePath, 'utf8');
    const config = JSON.parse(content);
    res.json(config);
  } catch (err) {
    const status = err.status || 404;
    res.status(status).json({ error: err.status === 400 ? err.message : 'Template not found' });
  }
});

export default router;
