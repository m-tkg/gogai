/// <reference types="vitest/config" />
import { defineConfig } from 'vite'
import react from '@vitejs/plugin-react'

// https://vite.dev/config/
export default defineConfig({
  plugins: [react()],
  server: {
    host: '0.0.0.0',
    allowedHosts: true,
    proxy: {
      '/api': 'http://localhost:3040',
    },
  },
  // Raspberry Pi デーモン(gogai-frontend.service)は vite preview でビルド済み dist/ を配信するため、
  // server と同じネットワーク設定・API プロキシを preview 側にも用意する
  preview: {
    host: '0.0.0.0',
    allowedHosts: true,
    port: 5173,
    proxy: {
      '/api': 'http://localhost:3040',
    },
  },
  test: {
    environment: 'jsdom',
    setupFiles: ['./src/test/setup.ts'],
  },
})
