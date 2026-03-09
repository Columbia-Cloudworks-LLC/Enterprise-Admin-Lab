import express from 'express';
import cors from 'cors';
import path from 'path';
import { fileURLToPath } from 'url';
import fs from 'fs';

// Routes
import labsRouter from './routes/labs.js';
import defaultsRouter from './routes/defaults.js';
import schemaRouter from './routes/schema.js';
import templatesRouter from './routes/templates.js';
import prerequisitesRouter from './routes/prerequisites.js';

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);
const app = express();

// Determine port based on environment
const isDev = process.env.NODE_ENV !== 'production';
const port = isDev ? 47001 : 47000;

// Restrict CORS to known localhost origins only — never allow arbitrary external origins
const allowedOrigins = isDev
  ? ['http://localhost:47173']          // Vite dev server
  : ['http://localhost:47000'];         // Production self-origin

const corsOptions = {
  origin: (origin, callback) => {
    // Allow requests with no Origin header (e.g. curl, Postman, same-origin)
    if (!origin || allowedOrigins.includes(origin)) {
      callback(null, true);
    } else {
      callback(new Error(`CORS: origin '${origin}' not allowed`));
    }
  },
  methods: ['GET', 'POST', 'PUT', 'PATCH', 'DELETE', 'OPTIONS'],
  allowedHeaders: ['Content-Type', 'Authorization'],
  credentials: false,
};

// Middleware
app.use(express.json());
app.use(cors(corsOptions));

// Mount API routes
app.use('/api/labs', labsRouter);
app.use('/api/defaults', defaultsRouter);
app.use('/api/schema', schemaRouter);
app.use('/api/templates', templatesRouter);
app.use('/api/prerequisites', prerequisitesRouter);

// Health check endpoint — must be before static/wildcard
app.get('/health', (req, res) => {
  res.json({ status: 'ok' });
});

// API 404 catch-all — unmatched /api/* routes return JSON, never index.html
app.use('/api', (req, res) => {
  res.status(404).json({ error: 'Not Found' });
});

// Production: serve static files from ../dist, with SPA fallback
if (!isDev) {
  const distPath = path.resolve(__dirname, '../dist');
  app.use(express.static(distPath));
  app.get('*', (req, res) => {
    res.sendFile(path.join(distPath, 'index.html'));
  });
}

// Dev 404 handler (unreachable in production — wildcard above handles it)
app.use((req, res) => {
  res.status(404).json({ error: 'Not Found' });
});

// Error handler
app.use((err, req, res, next) => {
  console.error(err);
  res.status(err.status || 500).json({ error: 'An internal error occurred' });
});

// Start server
const server = app.listen(port, () => {
  console.log(`[EALab Server] Express API running on port ${port}`);
  if (isDev) {
    console.log('[EALab Server] Vite dev server should be running on port 47173');
    console.log('[EALab Server] Open http://localhost:47173 in your browser');
  }
});

// Graceful shutdown
process.on('SIGINT', () => {
  console.log('\n[EALab Server] Shutting down...');
  server.close(() => {
    console.log('[EALab Server] Server closed');
    process.exit(0);
  });
});
