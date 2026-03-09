import express from 'express';
import path from 'path';
import { fileURLToPath } from 'url';
import fs from 'fs/promises';

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);

const router = express.Router();
const configDir = path.resolve(__dirname, '../../../Config');

// GET /api/defaults - return Config/defaults.json
router.get('/', async (req, res) => {
  try {
    const filePath = path.join(configDir, 'defaults.json');
    const content = await fs.readFile(filePath, 'utf8');
    const data = JSON.parse(content);
    res.json(data);
  } catch (err) {
    res.status(500).json({ error: 'Failed to read defaults.json' });
  }
});

export default router;
