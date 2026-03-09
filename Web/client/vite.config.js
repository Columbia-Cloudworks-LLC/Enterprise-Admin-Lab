import { defineConfig } from 'vite';
import react from '@vitejs/plugin-react';
import tailwindcss from '@tailwindcss/vite';

export default defineConfig({
  plugins: [react(), tailwindcss()],
  server: {
    port: 47173,
    proxy: {
      '/api': {
        target: 'http://localhost:47001',
        changeOrigin: true,
      },
    },
  },
});
